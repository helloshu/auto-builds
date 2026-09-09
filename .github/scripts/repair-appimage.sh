#!/usr/bin/env bash

# Repair the Tauri/linuxdeploy GTK AppImage runtime for Debian 13/KDE Wayland
# while keeping the AppImage's original outer runtime. This script is strict:
# an unexpected AppImage layout is a build failure, not a reason to publish an
# unverified binary.

set -euo pipefail

# These paths are assigned later. Initialize them before the EXIT trap so a
# failure during setup cannot make cleanup inspect unset variables.
TMP_ROOT=''
APPIMAGE_DIR=''
APPIMAGE_BASE=''
REPLACEMENT=''

die() {
    echo "::error::$*" >&2
    exit 1
}

usage() {
    echo "Usage: $0 APPIMAGE APPIMAGETOOL" >&2
}

if [ "$#" -ne 2 ]; then
    usage
    exit 2
fi

SCRIPT_PATH=$(realpath -- "${BASH_SOURCE[0]}") || die "无法解析修整脚本路径"
SCRIPT_DIR=$(dirname -- "$SCRIPT_PATH")
REWRITE_SCRIPT="$SCRIPT_DIR/rewrite-appimage-runtime.py"
PYTHON=${PYTHON:-python3}
command -v "$PYTHON" >/dev/null 2>&1 || die "找不到 Python 解释器: $PYTHON"
[ -f "$REWRITE_SCRIPT" ] || die "缺少 GTK hook 重写辅助脚本: $REWRITE_SCRIPT"

APPIMAGE=$(realpath -- "$1") || die "无法解析 AppImage 路径: $1"
APPIMAGETOOL=$(realpath -- "$2") || die "无法解析 appimagetool 路径: $2"

[ -f "$APPIMAGE" ] || die "AppImage 不是普通文件: $APPIMAGE"
[ -x "$APPIMAGE" ] || die "AppImage 不可执行: $APPIMAGE"
[ -f "$APPIMAGETOOL" ] || die "appimagetool 不是普通文件: $APPIMAGETOOL"
[ -x "$APPIMAGETOOL" ] || die "appimagetool 不可执行: $APPIMAGETOOL"

TMP_ROOT=$(mktemp -d)
TMP_ROOT=$(realpath -- "$TMP_ROOT")

cleanup_replacement() {
    local replacement_parent=''
    local replacement_name=''
    local expected_name=''
    local expected_path=''
    local resolved_parent=''

    # Only remove the exact temporary path this invocation creates. In
    # particular, do not follow a changed/symlinked parent directory.
    if [ -z "${REPLACEMENT:-}" ] || [ -z "${APPIMAGE_DIR:-}" ] || [ -z "${APPIMAGE_BASE:-}" ]; then
        return 0
    fi
    [ -d "$APPIMAGE_DIR" ] || return 0
    replacement_parent=$(dirname -- "$REPLACEMENT") || return 0
    replacement_name=$(basename -- "$REPLACEMENT") || return 0
    expected_name=".${APPIMAGE_BASE}.replacement.$$"
    expected_path="$APPIMAGE_DIR/$expected_name"
    [ "$REPLACEMENT" = "$expected_path" ] || return 0
    [ "$replacement_parent" = "$APPIMAGE_DIR" ] || return 0
    [ "$replacement_name" = "$expected_name" ] || return 0
    resolved_parent=$(realpath -- "$APPIMAGE_DIR") || return 0
    [ "$resolved_parent" = "$APPIMAGE_DIR" ] || return 0
    if [ -f "$REPLACEMENT" ] || [ -L "$REPLACEMENT" ]; then
        rm -f -- "$REPLACEMENT"
    fi
}

cleanup() {
    # TMP_ROOT is created by mktemp above; never broaden this cleanup target.
    if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ] && [ "$TMP_ROOT" != "/" ]; then
        rm -rf -- "$TMP_ROOT"
    fi
    cleanup_replacement
}
trap cleanup EXIT

assert_inside_tmp() {
    local candidate=$1
    local resolved
    resolved=$(realpath -m -- "$candidate") || die "无法解析临时路径: $candidate"
    case "$resolved" in
        "$TMP_ROOT"/*) ;;
        *) die "拒绝访问临时目录之外的路径: $candidate -> $resolved" ;;
    esac
}

assert_inside_appdir() {
    local candidate=$1
    local resolved
    resolved=$(realpath -m -- "$candidate") || die "无法解析 AppDir 路径: $candidate"
    case "$resolved" in
        "$APPDIR"/*) ;;
        *) die "拒绝访问 AppDir 之外的路径: $candidate -> $resolved" ;;
    esac
}

extract_appimage() {
    local source=$1
    local destination=$2
    assert_inside_tmp "$destination"
    mkdir -p -- "$destination"
    (
        cd -- "$destination"
        "$source" --appimage-extract >/dev/null
    )
    [ -d "$destination/squashfs-root" ] || die "AppImage 解包后缺少 squashfs-root"
    realpath -- "$destination/squashfs-root"
}

find_gtk_hook() {
    local root=$1
    local hooks=()
    while IFS= read -r -d '' hook; do
        hooks+=("$hook")
    done < <(find "$root" -type f -path '*/apprun-hooks/linuxdeploy-plugin-gtk.sh' -print0)

    if [ "${#hooks[@]}" -ne 1 ]; then
        die "预期唯一 GTK hook，实际找到 ${#hooks[@]} 个"
    fi
    local resolved
    resolved=$(realpath -- "${hooks[0]}") || die "无法解析 GTK hook: ${hooks[0]}"
    assert_inside_tmp "$resolved"
    printf '%s\n' "$resolved"
}

count_gdk_exports() {
    local hook=$1
    grep -Ec '^[[:space:]]*export[[:space:]]+GDK_BACKEND[[:space:]]*=' "$hook" || true
}

count_plain_gdk_exports() {
    local hook=$1
    grep -Ec '^[[:space:]]*export[[:space:]]+GDK_BACKEND[[:space:]]*$' "$hook" || true
}

find_gio_modules() {
    local root=$1
    local preferred="$root/usr/lib/x86_64-linux-gnu/gio/modules"
    if [ -d "$preferred" ]; then
        local resolved
        resolved=$(realpath -- "$preferred") || die "无法解析 GIO modules 目录: $preferred"
        assert_inside_tmp "$resolved"
        printf '%s\n' "$resolved"
        return 0
    fi

    local candidates=()
    while IFS= read -r -d '' directory; do
        candidates+=("$directory")
    done < <(find "$root/usr" -type d -path '*/gio/modules' -print0)
    if [ "${#candidates[@]}" -ne 1 ]; then
        die "找不到唯一的包内 GIO modules 目录（预期 Debian x86_64 路径）"
    fi
    local resolved
    resolved=$(realpath -- "${candidates[0]}") || die "无法解析 GIO modules 目录: ${candidates[0]}"
    assert_inside_tmp "$resolved"
    printf '%s\n' "$resolved"
}

rewrite_gtk_hook() {
    local hook=$1
    local modules_dir=$2
    "$PYTHON" "$REWRITE_SCRIPT" \
        --hook "$hook" \
        --appdir "$APPDIR" \
        --gio-modules "$modules_dir"
}

remove_packaged_wayland() {
    local root=$1
    local patterns=(
        'libwayland-client.so*'
        'libwayland-cursor.so*'
        'libwayland-egl.so*'
        'libwayland-server.so*'
    )
    local pattern path resolved
    for pattern in "${patterns[@]}"; do
        while IFS= read -r -d '' path; do
            assert_inside_tmp "$path"
            assert_inside_appdir "$path"
            resolved=$(realpath -m -- "$path") || die "无法解析待删除 Wayland 库: $path"
            case "$resolved" in
                "$APPDIR"/*) ;;
                *) die "待删除 Wayland 库解析到了 AppDir 外: $path -> $resolved" ;;
            esac
            rm -f -- "$path"
        done < <(find "$root" \( -type f -o -type l \) -name "$pattern" -print0)
    done

    local leftovers=()
    while IFS= read -r -d '' path; do
        leftovers+=("$path")
    done < <(
        find "$root" \( -type f -o -type l \) \( \
            -name 'libwayland-client.so*' -o \
            -name 'libwayland-cursor.so*' -o \
            -name 'libwayland-egl.so*' -o \
            -name 'libwayland-server.so*' \
        \) -print0
    )
    [ "${#leftovers[@]}" -eq 0 ] || die "AppDir 仍残留包内 Wayland 平台库"
}

repair_dir_icon() {
    local icon="$APPDIR/.DirIcon"
    case "$icon" in
        "$APPDIR"/*) ;;
        *) die "拒绝访问 AppDir 之外的路径: $icon" ;;
    esac

    local rebuild=0
    if [ -L "$icon" ]; then
        local target
        if target=$(realpath -- "$icon" 2>/dev/null); then
            case "$target" in
                "$APPDIR"/*)
                    if [ -f "$target" ]; then
                        local relative
                        relative=$(realpath --relative-to="$APPDIR" -- "$target")
                        [ -n "$relative" ] || die "无法计算 .DirIcon 相对路径"
                        rm -f -- "$icon"
                        ln -s -- "$relative" "$icon"
                    else
                        rebuild=1
                    fi
                    ;;
                *)
                    # Do not inspect a target outside the AppDir. The link is
                    # stale or unsafe and will be reconstructed from desktop
                    # metadata below.
                    rebuild=1
                    ;;
            esac
        else
            rebuild=1
        fi
    elif [ -f "$icon" ]; then
        [ -s "$icon" ] || die ".DirIcon 是空文件"
    else
        rebuild=1
    fi

    if [ "$rebuild" -eq 1 ]; then
        # Tauri normally supplies .DirIcon. If a newer bundler omits it, or
        # supplies a stale/unsafe link, reconstruct it from the single root
        # desktop file and its safe icon name.
        rm -f -- "$icon"

        local desktops=()
        while IFS= read -r -d '' desktop; do
            desktops+=("$desktop")
        done < <(find "$APPDIR" -maxdepth 1 -type f -name '*.desktop' -print0)
        [ "${#desktops[@]}" -eq 1 ] || die "缺少 .DirIcon，且无法定位唯一根目录 desktop 文件"

        local icon_values=()
        local icon_value
        while IFS= read -r icon_value; do
            icon_values+=("$icon_value")
        done < <(sed -nE 's/^[[:space:]]*Icon[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' "${desktops[0]}")
        [ "${#icon_values[@]}" -eq 1 ] || die "缺少 .DirIcon，desktop 文件必须有唯一的 Icon 字段"

        local icon_name="${icon_values[0]}"
        [[ "$icon_name" =~ ^[A-Za-z0-9][-A-Za-z0-9._+]*$ ]] || die "拒绝不安全的 Icon 名称: $icon_name"
        [ "$icon_name" != "." ] || die "拒绝不安全的 Icon 名称: $icon_name"
        [ "$icon_name" != ".." ] || die "拒绝不安全的 Icon 名称: $icon_name"

        local candidates=()
        local candidate base resolved
        while IFS= read -r -d '' candidate; do
            base=$(basename -- "$candidate")
            if [ "$base" = "$icon_name" ] || [[ "$base" == "$icon_name".* ]]; then
                resolved=$(realpath -- "$candidate") || die "无法解析候选图标: $candidate"
                case "$resolved" in
                    "$APPDIR"/*) ;;
                    *) die "候选图标解析到了 AppDir 外: $candidate -> $resolved" ;;
                esac
                [ -f "$candidate" ] || die "候选图标不是普通文件: $candidate"
                [ ! -L "$candidate" ] || die "候选图标不得是软链接: $candidate"
                candidates+=("$resolved")
            fi
        done < <(find "$APPDIR" -maxdepth 1 -type f ! -name '*.desktop' -print0)

        # Tauri may place the icon beside the root desktop file. Prefer a
        # unique root-level match; only fall back to usr/share when the root
        # has no matching ordinary file.
        if [ "${#candidates[@]}" -eq 0 ]; then
            while IFS= read -r -d '' candidate; do
                base=$(basename -- "$candidate")
                if [ "$base" = "$icon_name" ] || [[ "$base" == "$icon_name".* ]]; then
                    resolved=$(realpath -- "$candidate") || die "无法解析候选图标: $candidate"
                    case "$resolved" in
                        "$APPDIR"/*) ;;
                        *) die "候选图标解析到了 AppDir 外: $candidate -> $resolved" ;;
                    esac
                    [ -f "$candidate" ] || die "候选图标不是普通文件: $candidate"
                    [ ! -L "$candidate" ] || die "候选图标不得是软链接: $candidate"
                    candidates+=("$resolved")
                fi
            done < <(find "$APPDIR/usr/share" -type f -print0 2>/dev/null || true)
        fi
        [ "${#candidates[@]}" -eq 1 ] || die "缺少 .DirIcon，无法从 Icon=$icon_name 定位唯一图标"

        local relative
        relative=$(realpath --relative-to="$APPDIR" -- "${candidates[0]}")
        [ -n "$relative" ] || die "无法计算 .DirIcon 相对路径"
        ln -s -- "$relative" "$icon"
    fi

    if [ -L "$icon" ]; then
        local final_target
        final_target=$(realpath -- "$icon") || die ".DirIcon 修整后仍是失效软链接"
        assert_inside_tmp "$final_target"
        assert_inside_appdir "$final_target"
        [ -f "$final_target" ] || die ".DirIcon 修整后目标不存在"
    fi
}

validate_dir_icon() {
    local icon="$APPDIR/.DirIcon"
    assert_inside_appdir "$icon"
    if [ -L "$icon" ]; then
        local target
        target=$(realpath -- "$icon") || die "验证失败：.DirIcon 是失效软链接"
        assert_inside_tmp "$target"
        assert_inside_appdir "$target"
        [ -f "$target" ] || die "验证失败：.DirIcon 目标不存在"
    elif [ -f "$icon" ]; then
        [ -s "$icon" ] || die "验证失败：.DirIcon 是空文件"
    else
        die "验证失败：缺少 .DirIcon"
    fi
}

verify_appdir() {
    local root=$1
    local hook
    APPDIR=$(realpath -- "$root")
    assert_inside_tmp "$APPDIR"
    hook=$(find_gtk_hook "$APPDIR")
    [ "$(count_gdk_exports "$hook")" -eq 0 ] || die "验证失败：GTK hook 中仍有旧式 GDK_BACKEND export"
    [ "$(count_plain_gdk_exports "$hook")" -eq 1 ] || die "验证失败：GTK hook 中 GDK_BACKEND export 数量错误"
    grep -Fq 'GDK_BACKEND="wayland,x11"' "$hook" || die "验证失败：缺少 Wayland 优先逻辑"
    grep -Fq 'GDK_BACKEND="x11"' "$hook" || die "验证失败：缺少 X11 回退逻辑"

    local modules_dir
    modules_dir=$(find_gio_modules "$APPDIR")
    [ -d "$modules_dir" ] || die "验证失败：GIO modules 目录不存在"
    local relative expected
    relative=$(realpath --relative-to="$APPDIR" -- "$modules_dir")
    expected="export GIO_MODULE_DIR=\"\$APPDIR/$relative\""
    grep -Fqx "$expected" "$hook" || die "验证失败：缺少正确的 GIO_MODULE_DIR export"

    local path
    while IFS= read -r -d '' path; do
        die "验证失败：残留包内 Wayland 平台库: $path"
    done < <(
        find "$APPDIR" \( -type f -o -type l \) \( \
            -name 'libwayland-client.so*' -o \
            -name 'libwayland-cursor.so*' -o \
            -name 'libwayland-egl.so*' -o \
            -name 'libwayland-server.so*' \
        \) -print0
    )
    [ -e "$APPDIR/AppRun" ] || die "验证失败：缺少 AppRun"
    local desktop_count
    desktop_count=$(find "$APPDIR" -maxdepth 1 -type f -name '*.desktop' | wc -l)
    [ "$desktop_count" -eq 1 ] || die "验证失败：根目录 desktop 文件应为 1 个，实际为 $desktop_count"
    validate_dir_icon
}

EXTRACT_DIR="$TMP_ROOT/extracted"
APPDIR=$(extract_appimage "$APPIMAGE" "$EXTRACT_DIR")
HOOK=$(find_gtk_hook "$APPDIR")
GIO_MODULES=$(find_gio_modules "$APPDIR")

rewrite_gtk_hook "$HOOK" "$GIO_MODULES"
remove_packaged_wayland "$APPDIR"
repair_dir_icon
verify_appdir "$APPDIR"

APPIMAGE_DIR=$(dirname -- "$APPIMAGE")
APPIMAGE_BASE=$(basename -- "$APPIMAGE")
REPACK_DIR="$TMP_ROOT/repack"
mkdir -p -- "$REPACK_DIR"
REPACKED="$REPACK_DIR/$APPIMAGE_BASE"

echo "使用传入的 appimagetool 重新封装: $APPIMAGETOOL"
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run "$APPDIR" "$REPACKED"
[ -s "$REPACKED" ] || die "appimagetool 未生成非空 AppImage"
chmod +x -- "$REPACKED"

REPLACEMENT="$APPIMAGE_DIR/.${APPIMAGE_BASE}.replacement.$$"
if [ -e "$REPLACEMENT" ] || [ -L "$REPLACEMENT" ]; then
    die "替换临时文件已存在，拒绝覆盖: $REPLACEMENT"
fi
cp -- "$REPACKED" "$REPLACEMENT"
chmod +x -- "$REPLACEMENT"
mv -f -- "$REPLACEMENT" "$APPIMAGE"

VERIFY_DIR="$TMP_ROOT/verify"
VERIFY_APPDIR=$(extract_appimage "$APPIMAGE" "$VERIFY_DIR")
verify_appdir "$VERIFY_APPDIR"

"$APPIMAGE" --appimage-help >/dev/null
OFFSET=$("$APPIMAGE" --appimage-offset | tr -d '\r\n')
[[ "$OFFSET" =~ ^[0-9]+$ ]] || die "最终 AppImage --appimage-offset 输出无效: $OFFSET"

echo "AppImage 修整并验证成功: $APPIMAGE (offset=$OFFSET)"
