#!/usr/bin/env python3
"""Resilient, mirror-aware Zig toolchain installer with mandatory SHA-256 verification.

Downloads a pinned Zig archive from shuffled official Zig community mirrors
(falling back to ziglang.org with backoff retries), verifies its hardcoded
SHA-256 digest before extraction, caches the verified archive for subsequent
runs, and appends the extracted binary directory to GITHUB_PATH.
"""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

MIRRORS_LIST_URL = "https://ziglang.org/download/community-mirrors.txt"

FALLBACK_MIRRORS = [
    "https://pkg.machengine.org/zig",
    "https://zigmirror.hryx.net/zig",
    "https://zig.linus.dev/zig",
    "https://zig.squirl.dev",
    "https://zig.mirror.mschae23.de/zig",
    "https://ziglang.freetls.fastly.net",
    "https://zig.tilok.dev",
    "https://zig-mirror.tsimnet.eu/zig",
    "https://zig.karearl.com/zig",
    "https://pkg.earth/zig",
    "https://fs.liujiacai.net/zigbuilds",
    "https://zigmirror.com",
    "https://zig.chainsafe.dev",
    "https://zig.savalione.com",
]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(256 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch_mirrors() -> list[str]:
    req = urllib.request.Request(
        MIRRORS_LIST_URL,
        headers={"User-Agent": "auto-builds-zig-installer"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
        mirrors = [
            ln.strip().rstrip("/")
            for ln in raw.splitlines()
            if ln.strip().startswith("https://")
        ]
        if mirrors:
            return mirrors
    except Exception as exc:
        print(f"[zig] could not fetch mirror list ({exc}); using built-in mirror list", flush=True)
    return list(FALLBACK_MIRRORS)


def download_and_verify(url: str, dest: Path, expected_sha256: str) -> None:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "auto-builds-zig-installer"},
    )
    tmp_path = dest.with_name(f".{dest.name}.{os.getpid()}.part")
    h = hashlib.sha256()
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            status = getattr(resp, "status", None)
            if status is not None and status != 200:
                raise RuntimeError(f"HTTP {status}")
            dest.parent.mkdir(parents=True, exist_ok=True)
            with tmp_path.open("wb") as out_fh:
                while True:
                    chunk = resp.read(256 * 1024)
                    if not chunk:
                        break
                    h.update(chunk)
                    out_fh.write(chunk)
        actual = h.hexdigest()
        if actual != expected_sha256:
            raise RuntimeError(f"SHA-256 mismatch: expected {expected_sha256}, got {actual}")
        shutil.move(str(tmp_path), str(dest))
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise


def ensure_verified_archive(
    version: str, archive_name: str, expected_sha256: str, cache_dir: Path
) -> Path:
    cache_dir.mkdir(parents=True, exist_ok=True)
    cached = cache_dir / archive_name
    if cached.is_file():
        actual = sha256_file(cached)
        if actual == expected_sha256:
            print(f"[zig] cache hit (SHA-256 verified): {cached}", flush=True)
            return cached
        print(f"[zig] removing stale cached archive (got {actual})", flush=True)
        cached.unlink(missing_ok=True)

    mirrors = fetch_mirrors()
    random.shuffle(mirrors)

    candidates: list[tuple[str, float]] = [
        (f"{m}/{archive_name}?source=auto-builds", 0.0) for m in mirrors[:8]
    ]
    canonical = f"https://ziglang.org/download/{version}/{archive_name}"
    for delay in (0.0, 5.0, 12.0, 25.0):
        candidates.append((canonical, delay))

    last_err: Exception | None = None
    for idx, (url, delay) in enumerate(candidates, 1):
        if delay > 0:
            time.sleep(delay)
        try:
            print(f"[zig] attempt {idx}/{len(candidates)}: {url}", flush=True)
            download_and_verify(url, cached, expected_sha256)
            print(f"[zig] verified SHA-256 ({expected_sha256[:16]}...) from {url}", flush=True)
            return cached
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError, RuntimeError) as exc:
            last_err = exc
            print(f"[zig] warning: source failed ({exc})", flush=True)

    raise SystemExit(f"ERROR: exhausted all Zig mirrors and retries for {archive_name}: {last_err}")


def extract_archive(archive_path: Path, dest_dir: Path) -> Path:
    stage_dir = dest_dir.parent / f"zig-extract-{os.getpid()}"
    shutil.rmtree(stage_dir, ignore_errors=True)
    shutil.rmtree(dest_dir, ignore_errors=True)
    stage_dir.mkdir(parents=True, exist_ok=True)

    try:
        if archive_path.name.endswith(".zip"):
            with zipfile.ZipFile(archive_path) as zf:
                stage_resolved = stage_dir.resolve()
                for member in zf.infolist():
                    target = (stage_resolved / member.filename).resolve()
                    if stage_resolved != target and stage_resolved not in target.parents:
                        raise SystemExit(f"ERROR: unsafe zip member path: {member.filename}")
                zf.extractall(stage_resolved)
        else:
            subprocess.run(["tar", "-xf", str(archive_path), "-C", str(stage_dir)], check=True)

        subdirs = [p for p in stage_dir.iterdir() if p.is_dir()]
        if len(subdirs) == 1:
            shutil.move(str(subdirs[0]), str(dest_dir))
        else:
            shutil.move(str(stage_dir), str(dest_dir))
    finally:
        shutil.rmtree(stage_dir, ignore_errors=True)

    return dest_dir


def main() -> None:
    parser = argparse.ArgumentParser(description="Install pinned Zig with mirror fallback and SHA-256 verification")
    parser.add_argument("version", help="Zig release version (e.g. 0.17.0)")
    parser.add_argument("archive", help="Archive filename (e.g. zig-x86_64-linux-0.17.0.tar.xz)")
    parser.add_argument("sha256", help="Expected 64-char lowercase hex SHA-256")
    parser.add_argument("--cache-dir", default="", help="Directory to store SHA-256 verified archive")
    args = parser.parse_args()

    expected_sha = args.sha256.strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected_sha):
        raise SystemExit(f"ERROR: invalid SHA-256 digest: {args.sha256!r}")
    if "/" in args.archive or "\\" in args.archive or ".." in args.archive:
        raise SystemExit(f"ERROR: invalid archive filename: {args.archive!r}")

    cache_dir = (
        Path(args.cache_dir).expanduser().resolve()
        if args.cache_dir
        else (Path.home() / ".cache" / "zig-archives").resolve()
    )
    verified_archive = ensure_verified_archive(args.version.strip(), args.archive.strip(), expected_sha, cache_dir)

    runner_temp = Path(os.environ.get("RUNNER_TEMP") or tempfile.gettempdir()).resolve()
    dest_dir = extract_archive(verified_archive, runner_temp / "zig")

    zig_bin = dest_dir / ("zig.exe" if os.name == "nt" else "zig")
    if not zig_bin.is_file():
        raise SystemExit(f"ERROR: Zig binary not found at {zig_bin}")

    out = subprocess.check_output([str(zig_bin), "version"], text=True).strip()
    print(f"[zig] installed zig {out} at {zig_bin}", flush=True)

    gh_path = os.environ.get("GITHUB_PATH")
    if gh_path:
        with open(gh_path, "a", encoding="utf-8", newline="\n") as fh:
            fh.write(f"{dest_dir}\n")


if __name__ == "__main__":
    main()
