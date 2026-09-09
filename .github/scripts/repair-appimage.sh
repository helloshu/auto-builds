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
ROOT_DESKTOP=''

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

validate_root_desktop() {
    local root=$1
    local desktops=()
    local desktop
    while IFS= read -r -d '' desktop; do
        desktops+=("$desktop")
    done < <(find "$root" -maxdepth 1 \( -type f -o -type l \) -name '*.desktop' -print0)
    [ "${#desktops[@]}" -eq 1 ] || die "验证失败：根目录 desktop 路径应为 1 个，实际为 ${#desktops[@]}"

    desktop=${desktops[0]}
    case "$desktop" in
        "$root"/*) ;;
        *) die "验证失败：根目录 desktop 路径不在 AppDir 内: $desktop" ;;
    esac

    if [ -L "$desktop" ]; then
        local target
        target=$(realpath -- "$desktop") || die "验证失败：根目录 desktop 是失效软链接: $desktop"
        case "$target" in
            "$root"/*) ;;
            *) die "验证失败：根目录 desktop 解析到了 AppDir 外: $desktop -> $target" ;;
        esac
        [ -f "$target" ] || die "验证失败：根目录 desktop 目标不是普通文件: $target"
        [ ! -L "$target" ] || die "验证失败：根目录 desktop 目标仍是软链接: $target"
        [ -s "$target" ] || die "验证失败：根目录 desktop 目标是空文件: $target"
    else
        [ -f "$desktop" ] || die "验证失败：根目录 desktop 不是普通文件: $desktop"
        [ -s "$desktop" ] || die "验证失败：根目录 desktop 是空文件: $desktop"
    fi

    printf '%s\n' "$desktop"
}

find_trusted_desktop_copy() {
    local root=$1
    local name=$2
    local applications="$root/usr/share/applications"
    local applications_resolved=''
    local candidates=()
    local candidate resolved

    # Prefer an exact basename below the conventional applications directory.
    # Do not follow an applications directory that escapes the AppDir, and do
    # not accept symlink candidates.
    if [ -e "$applications" ] || [ -L "$applications" ]; then
        [ -d "$applications" ] || die "根目录 desktop 的可信副本目录不是目录: $applications"
        applications_resolved=$(realpath -- "$applications") || die "无法解析 desktop 可信副本目录: $applications"
        case "$applications_resolved" in
            "$root"/*) ;;
            *) die "拒绝访问 AppDir 之外的 desktop 可信副本目录: $applications -> $applications_resolved" ;;
        esac
        while IFS= read -r -d '' candidate; do
            [ "$(basename -- "$candidate")" = "$name" ] || continue
            resolved=$(realpath -- "$candidate") || die "无法解析 desktop 可信副本: $candidate"
            case "$resolved" in
                "$root"/*) ;;
                *) die "desktop 可信副本解析到了 AppDir 外: $candidate -> $resolved" ;;
            esac
            [ -f "$candidate" ] || die "desktop 可信副本不是普通文件: $candidate"
            [ ! -L "$candidate" ] || die "desktop 可信副本不得是软链接: $candidate"
            [ -s "$candidate" ] || die "desktop 可信副本是空文件: $candidate"
            candidates+=("$candidate")
        done < <(find "$applications_resolved" -maxdepth 1 -type f -print0)
    fi

    if [ "${#candidates[@]}" -gt 1 ]; then
        die "根目录 desktop 的可信副本不唯一: $name"
    elif [ "${#candidates[@]}" -eq 1 ]; then
        printf '%s\n' "${candidates[0]}"
        return 0
    fi

    die "无法从 usr/share/applications 定位唯一可信的 desktop 副本: $name"
}

normalize_root_desktop() {
    local root=$1
    local desktops=()
    local desktop
    while IFS= read -r -d '' desktop; do
        desktops+=("$desktop")
    done < <(find "$root" -maxdepth 1 \( -type f -o -type l \) -name '*.desktop' -print0)
    [ "${#desktops[@]}" -eq 1 ] || die "根目录 desktop 路径应为 1 个，实际为 ${#desktops[@]}"

    desktop=${desktops[0]}
    case "$desktop" in
        "$root"/*) ;;
        *) die "根目录 desktop 路径不在 AppDir 内: $desktop" ;;
    esac

    if [ -L "$desktop" ]; then
        local target=''
        local target_is_safe=0
        if target=$(realpath -- "$desktop" 2>/dev/null); then
            case "$target" in
                "$root"/*)
                    if [ -f "$target" ] && [ ! -L "$target" ] && [ -s "$target" ]; then
                        target_is_safe=1
                    fi
                    ;;
            esac
        fi

        if [ "$target_is_safe" -eq 1 ]; then
            # Normalize internal links so the repacked AppImage never depends
            # on an absolute or host-specific target.
            local relative
            relative=$(realpath --relative-to="$root" -- "$target") || die "无法计算根目录 desktop 相对路径"
            [ -n "$relative" ] || die "根目录 desktop 相对路径为空"
            rm -f -- "$desktop"
            ln -s -- "$relative" "$desktop"
        else
            # Do not inspect an external or invalid link. Rebuild it only from
            # an unambiguous, non-symlink, non-empty AppDir-internal copy.
            local trusted
            trusted=$(find_trusted_desktop_copy "$root" "$(basename -- "$desktop")")
            local relative
            relative=$(realpath --relative-to="$root" -- "$trusted") || die "无法计算可信 desktop 相对路径"
            [ -n "$relative" ] || die "可信 desktop 相对路径为空"
            rm -f -- "$desktop"
            ln -s -- "$relative" "$desktop"
        fi
    else
        [ -f "$desktop" ] || die "根目录 desktop 不是普通文件: $desktop"
        [ -s "$desktop" ] || die "根目录 desktop 是空文件: $desktop"
    fi

    validate_root_desktop "$root"
}

repair_dir_icon() {
    local icon="$APPDIR/.DirIcon"
    local desktop=${1:-}
    [ -n "$desktop" ] || die "修复 .DirIcon 时缺少已验证的根目录 desktop"
    case "$desktop" in
        "$APPDIR"/*.desktop) ;;
        *) die "根目录 desktop 不在 AppDir 内: $desktop" ;;
    esac
    # The caller passes the path returned by normalize_root_desktop. Keep a
    # second, non-mutating check here so Icon metadata is never read through an
    # external, stale, or empty desktop link.
    desktop=$(validate_root_desktop "$APPDIR")
    case "$icon" in
        "$APPDIR"/*) ;;
        *) die "拒绝访问 AppDir 之外的路径: $icon" ;;
    esac

    # Capture a symlink's raw target before any realpath/stat/delete operation
    # involving .DirIcon. The NUL-delimited read preserves embedded newlines
    # and other non-NUL bytes for the later control-character check.
    local link_text=''
    local is_symlink=0
    if IFS= read -r -d '' link_text < <(readlink -z -- "$icon" 2>/dev/null); then
        is_symlink=1
    elif [ -L "$icon" ]; then
        die "无法读取 .DirIcon 软链接文本"
    fi

    local recovery_hint=''
    local rebuild=0
    if [ "$is_symlink" -eq 1 ]; then
        local raw_hint_valid=1
        local raw_basename="${link_text##*/}"

        # Validate the raw link text before resolving or deleting anything.
        # An invalid hint is ignored and the desktop metadata fallback below
        # remains responsible for recovery.
        [ -n "$link_text" ] || raw_hint_valid=0
        case "$link_text" in
            */) raw_hint_valid=0 ;;
        esac
        [[ "$link_text" =~ [[:cntrl:]] ]] && raw_hint_valid=0
        [[ "$raw_basename" =~ ^[A-Za-z0-9][-A-Za-z0-9._+]*\.[A-Za-z0-9]+$ ]] || raw_hint_valid=0
        case "$raw_basename" in
            -*) raw_hint_valid=0 ;;
        esac

        local raw_rest="$link_text"
        local raw_component=''
        while :; do
            if [[ "$raw_rest" == */* ]]; then
                raw_component=${raw_rest%%/*}
                raw_rest=${raw_rest#*/}
            else
                raw_component=$raw_rest
                break
            fi
            case "$raw_component" in
                .|..) raw_hint_valid=0 ;;
            esac
        done
        case "$raw_rest" in
            .|..) raw_hint_valid=0 ;;
        esac
        if [ "$raw_hint_valid" -eq 1 ]; then
            recovery_hint="$raw_basename"
        fi

        local target=''
        local target_candidate=''
        local target_lexically_safe=$raw_hint_valid

        if [[ "$link_text" = /* ]]; then
            case "$link_text" in
                "$APPDIR"/*) target_candidate="$link_text" ;;
                *) target_lexically_safe=0 ;;
            esac
        else
            target_candidate="$APPDIR/$link_text"
        fi

        # Do not resolve through a symlinked target component. Such a path may
        # escape the AppDir; it is handled by the raw-hint recovery branch.
        if [ "$target_lexically_safe" -eq 1 ]; then
            local target_suffix
            if [[ "$link_text" = /* ]]; then
                target_suffix=${link_text#"$APPDIR"}
            else
                target_suffix="$link_text"
            fi
            local target_prefix="$APPDIR"
            local target_rest="$target_suffix"
            local target_component=''
            while :; do
                if [[ "$target_rest" == */* ]]; then
                    target_component=${target_rest%%/*}
                    target_rest=${target_rest#*/}
                else
                    target_component=$target_rest
                    target_rest=''
                fi
                if [ -n "$target_component" ]; then
                    target_prefix="$target_prefix/$target_component"
                    if [ -L "$target_prefix" ]; then
                        target_lexically_safe=0
                        break
                    fi
                fi
                [ -n "$target_rest" ] || break
            done
        fi

        if [ "$target_lexically_safe" -eq 1 ]; then
            if target=$(realpath -- "$target_candidate" 2>/dev/null); then
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
                    *) rebuild=1 ;;
                esac
            else
                rebuild=1
            fi
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
        # supplies a stale/unsafe link, reconstruct it from a safe recovery
        # hint or the single root desktop file and its safe icon name.
        rm -f -- "$icon"

        local candidates=()
        local candidate base resolved
        local icon_name=''
        if [ -n "$recovery_hint" ]; then
            while IFS= read -r -d '' candidate; do
                base=$(basename -- "$candidate")
                if [ "$base" = "$recovery_hint" ]; then
                    resolved=$(realpath -- "$candidate") || die "无法解析 .DirIcon 恢复候选: $candidate"
                    case "$resolved" in
                        "$APPDIR"/*) ;;
                        *) die ".DirIcon 恢复候选解析到了 AppDir 外: $candidate -> $resolved" ;;
                    esac
                    [ -f "$candidate" ] || die ".DirIcon 恢复候选不是普通文件: $candidate"
                    [ ! -L "$candidate" ] || die ".DirIcon 恢复候选不得是软链接: $candidate"
                    [ -s "$candidate" ] || die ".DirIcon 恢复候选是空文件: $candidate"
                    candidates+=("$resolved")
                fi
            done < <(find "$APPDIR" -maxdepth 1 -type f ! -name '*.desktop' -print0)
            [ "${#candidates[@]}" -le 1 ] || die ".DirIcon 恢复候选不唯一: $recovery_hint"
        fi

        if [ "${#candidates[@]}" -eq 0 ]; then
            local icon_values=()
            local icon_value
            while IFS= read -r icon_value; do
                icon_values+=("$icon_value")
            done < <(sed -nE 's/^[[:space:]]*Icon[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' "$desktop")
            [ "${#icon_values[@]}" -eq 1 ] || die "缺少 .DirIcon，desktop 文件必须有唯一的 Icon 字段"

            icon_name="${icon_values[0]}"
            [[ "$icon_name" =~ ^[A-Za-z0-9][-A-Za-z0-9._+]*$ ]] || die "拒绝不安全的 Icon 名称: $icon_name"
            [ "$icon_name" != "." ] || die "拒绝不安全的 Icon 名称: $icon_name"
            [ "$icon_name" != ".." ] || die "拒绝不安全的 Icon 名称: $icon_name"

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
                    [ -s "$candidate" ] || die "候选图标是空文件: $candidate"
                    candidates+=("$resolved")
                fi
            done < <(find "$APPDIR" -maxdepth 1 -type f ! -name '*.desktop' -print0)
        fi

        # Tauri may place the icon beside the root desktop file. Prefer a
        # unique root-level match; only fall back to usr/share when the root
        # has no matching ordinary file.
        if [ "${#candidates[@]}" -eq 0 ]; then
            local usr_share="$APPDIR/usr/share"
            if [ -e "$usr_share" ] || [ -L "$usr_share" ]; then
                [ -d "$usr_share" ] || die "候选图标目录不是目录: $usr_share"
                local usr_share_resolved
                usr_share_resolved=$(realpath -- "$usr_share") || die "无法解析候选图标目录: $usr_share"
                case "$usr_share_resolved" in
                    "$APPDIR"/*) ;;
                    *) die "候选图标目录解析到了 AppDir 外: $usr_share -> $usr_share_resolved" ;;
                esac
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
                        [ -s "$candidate" ] || die "候选图标是空文件: $candidate"
                        candidates+=("$resolved")
                    fi
                done < <(find "$usr_share_resolved" -type f -print0)
            fi
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
    validate_root_desktop "$APPDIR" >/dev/null
    validate_dir_icon
}

EXTRACT_DIR="$TMP_ROOT/extracted"
APPDIR=$(extract_appimage "$APPIMAGE" "$EXTRACT_DIR")
HOOK=$(find_gtk_hook "$APPDIR")
GIO_MODULES=$(find_gio_modules "$APPDIR")

rewrite_gtk_hook "$HOOK" "$GIO_MODULES"
remove_packaged_wayland "$APPDIR"
ROOT_DESKTOP=$(normalize_root_desktop "$APPDIR")
repair_dir_icon "$ROOT_DESKTOP"
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
