#!/usr/bin/env python3
"""Rewrite the small part of a linuxdeploy GTK hook we can verify safely.

The Tauri/linuxdeploy GTK hook is generated during a build.  Editing it with
``sed`` is tempting, but a changed hook layout can otherwise produce an
apparently successful yet unusable AppImage.  This helper therefore accepts
only a hook with exactly one GDK_BACKEND export, validates that every path is
inside the temporary AppDir, and writes an idempotent, explicit runtime setup.
"""

from __future__ import annotations

import argparse
import os
import re
import stat
import sys
from pathlib import Path


GDK_EXPORT_RE = re.compile(
    r"^[ \t]*export[ \t]+GDK_BACKEND[ \t]*=[^\r\n]*[ \t]*(?:\r?\n)?$"
)
GIO_EXPORT_RE = re.compile(
    r"^[ \t]*export[ \t]+GIO_MODULE_DIR[ \t]*=[^\r\n]*(?:\r?\n)?$"
)


def fail(message: str) -> "NoReturn":
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def resolve_existing(path_value: str, description: str) -> Path:
    path = Path(path_value)
    try:
        return path.resolve(strict=True)
    except OSError as exc:
        fail(f"无法解析{description}: {path_value} ({exc})")


def assert_child(path: Path, parent: Path, description: str) -> None:
    try:
        path.relative_to(parent)
    except ValueError:
        fail(f"{description} 不在临时 AppDir 内: {path}")


def line_ending(lines: list[str]) -> str:
    for line in lines:
        if line.endswith("\r\n"):
            return "\r\n"
        if line.endswith("\n"):
            return "\n"
    return os.linesep


def replacement_block(newline: str) -> str:
    return newline.join(
        [
            'if [ -z "${GDK_BACKEND:-}" ]; then',
            '    if [ -n "${WAYLAND_DISPLAY:-}" ]; then',
            '        GDK_BACKEND="wayland,x11"',
            "    else",
            '        GDK_BACKEND="x11"',
            "    fi",
            "    export GDK_BACKEND",
            "fi",
        ]
    )


def replace_line(line: str, replacement: str) -> str:
    if line.endswith("\r\n"):
        return replacement + "\r\n"
    if line.endswith("\n"):
        return replacement + "\n"
    return replacement


def rewrite_hook(hook: Path, appdir: Path, modules: Path) -> None:
    if not hook.is_file():
        fail(f"GTK hook 不是普通文件: {hook}")
    if not modules.is_dir():
        fail(f"GIO modules 不是目录: {modules}")

    assert_child(hook, appdir, "GTK hook")
    assert_child(modules, appdir, "GIO modules")

    try:
        text = hook.read_text(encoding="utf-8", newline="")
    except TypeError:
        # ``Path.read_text`` gained the newline argument only in newer
        # Python versions.  GitHub's Ubuntu runners have it, but retaining a
        # compatible fallback keeps this helper useful for local verification.
        with hook.open("r", encoding="utf-8", newline="") as stream:
            text = stream.read()
    lines = text.splitlines(keepends=True)
    newline = line_ending(lines)

    gdk_indices = [index for index, line in enumerate(lines) if GDK_EXPORT_RE.fullmatch(line)]
    gdk_replacement = replacement_block(newline)
    existing_block_count = text.count(gdk_replacement)
    if len(gdk_indices) > 1 or (len(gdk_indices) == 0 and existing_block_count != 1):
        fail(f"GTK hook 中 GDK_BACKEND 配置结构不受支持（旧 export {len(gdk_indices)} 条，已修整块 {existing_block_count} 条）")

    relative_modules = os.path.relpath(modules, appdir)
    if relative_modules in (".", "") or relative_modules == os.pardir or relative_modules.startswith(
        os.pardir + os.sep
    ):
        fail(f"GIO modules 相对路径无效: {modules}")
    relative_modules = relative_modules.replace(os.sep, "/")
    expected_gio = f'export GIO_MODULE_DIR="$APPDIR/{relative_modules}"'

    gio_indices = [index for index, line in enumerate(lines) if GIO_EXPORT_RE.fullmatch(line)]
    if len(gio_indices) > 1:
        fail(f"GTK hook 中 GIO_MODULE_DIR export 不应超过 1 条，实际为 {len(gio_indices)}")

    if gdk_indices:
        lines[gdk_indices[0]] = replace_line(lines[gdk_indices[0]], gdk_replacement)

    if gio_indices:
        lines[gio_indices[0]] = replace_line(lines[gio_indices[0]], expected_gio)
    else:
        if lines and not lines[-1].endswith(("\n", "\r")):
            lines[-1] += newline
        lines.append(expected_gio + newline)

    rewritten = "".join(lines)
    try:
        mode = stat.S_IMODE(hook.stat().st_mode)
        with hook.open("w", encoding="utf-8", newline="") as stream:
            stream.write(rewritten)
        os.chmod(hook, mode)
    except OSError as exc:
        fail(f"写入 GTK hook 失败: {hook} ({exc})")

    # Re-read and validate the exact forms that the shell launcher will use.
    try:
        verified = hook.read_text(encoding="utf-8", newline="")
    except TypeError:
        with hook.open("r", encoding="utf-8", newline="") as stream:
            verified = stream.read()
    verified_lines = verified.splitlines(keepends=True)
    if sum(1 for line in verified_lines if GDK_EXPORT_RE.fullmatch(line)) != 0:
        fail("GTK hook 修整后仍含旧式 GDK_BACKEND export")
    if replacement_block(newline) not in verified:
        fail("GTK hook 缺少 Wayland 优先、X11 回退逻辑")
    if verified.count(expected_gio) != 1:
        fail("GTK hook 缺少唯一且正确的 GIO_MODULE_DIR export")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hook", required=True, help="linuxdeploy GTK hook")
    parser.add_argument("--appdir", required=True, help="temporary extracted AppDir")
    parser.add_argument("--gio-modules", required=True, help="package GIO modules directory")
    args = parser.parse_args()

    appdir = resolve_existing(args.appdir, "临时 AppDir")
    hook = resolve_existing(args.hook, "GTK hook")
    modules = resolve_existing(args.gio_modules, "GIO modules")
    if not appdir.is_dir():
        fail(f"临时 AppDir 不是目录: {appdir}")
    assert_child(hook, appdir, "GTK hook")
    assert_child(modules, appdir, "GIO modules")
    rewrite_hook(hook, appdir, modules)
    print(f"已重写 GTK hook: {hook}")
    print(f"已锁定包内 GIO modules: {modules}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
