#!/usr/bin/env bash
# Authenticated cross-platform transit archive encryption, masking, and artifact cleanup.
#
# Subcommands:
#   transit-crypto.sh encrypt <src-dir> <out-enc-file>
#   transit-crypto.sh decrypt <in-enc-file> <dest-dir>
#   transit-crypto.sh load-env <resolved-env-file> [--export-github-env]
#   transit-crypto.sh purge-artifacts

set -euo pipefail

# Prefer Homebrew OpenSSL 3 on macOS when present so OpenSSL CLI flags behave identically.
for brew_ssl in /opt/homebrew/opt/openssl@3/bin /usr/local/opt/openssl@3/bin; do
  if [ -x "${brew_ssl}/openssl" ]; then
    export PATH="${brew_ssl}:${PATH}"
    break
  fi
done

PY_BIN="python3"
command -v "${PY_BIN}" >/dev/null 2>&1 || PY_BIN="python"

"${PY_BIN}" - "$@" <<'PY'
import gzip
import hashlib
import hmac
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request


def derive_keys() -> tuple[str, bytes]:
    secret = os.environ.get("TRANSIT_SECRET", "")
    if len(secret) < 16:
        raise SystemExit("ERROR: TRANSIT_SECRET must be set (>= 16 chars)")
    ctx = (
        f"{os.environ.get('GITHUB_REPOSITORY', 'local')}:"
        f"{os.environ.get('GITHUB_RUN_ID', '0')}:"
        f"{os.environ.get('GITHUB_RUN_ATTEMPT', '0')}"
    )
    enc_key = hmac.new(secret.encode("utf-8"), f"enc:{ctx}".encode("utf-8"), hashlib.sha256).hexdigest()
    mac_key = hmac.new(secret.encode("utf-8"), f"mac:{ctx}".encode("utf-8"), hashlib.sha256).digest()
    return enc_key, mac_key


def cmd_encrypt(src_dir_str: str, out_file_str: str) -> None:
    src_dir = Path(src_dir_str).resolve()
    out_file = Path(out_file_str).resolve()
    if not src_dir.is_dir():
        raise SystemExit(f"ERROR: source directory not found: {src_dir}")
    out_file.parent.mkdir(parents=True, exist_ok=True)
    enc_key, mac_key = derive_keys()

    with tempfile.TemporaryDirectory(prefix="r4-enc-") as tmp:
        tar_path = Path(tmp) / "payload.tar.gz"
        ct_path = Path(tmp) / "payload.ct"
        with gzip.GzipFile(filename=tar_path, mode="wb", compresslevel=6, mtime=0) as gz:
            with tarfile.open(fileobj=gz, mode="w") as tf:
                for item in sorted(src_dir.iterdir()):
                    tf.add(item, arcname=item.name)

        env = os.environ.copy()
        env["TRANSIT_ENC_KEY"] = enc_key
        subprocess.run(
            [
                "openssl", "enc", "-aes-256-cbc", "-md", "sha256",
                "-pbkdf2", "-iter", "200000", "-salt",
                "-pass", "env:TRANSIT_ENC_KEY",
                "-in", str(tar_path), "-out", str(ct_path),
            ],
            env=env,
            check=True,
        )
        ciphertext = ct_path.read_bytes()
        tag_hex = hmac.new(mac_key, ciphertext, hashlib.sha256).hexdigest()
        with out_file.open("wb") as out_fh:
            out_fh.write(b"R4ENC1\n")
            out_fh.write(tag_hex.encode("ascii") + b"\n")
            out_fh.write(ciphertext)


def safe_extract_tar(tf: tarfile.TarFile, dest_dir: Path) -> None:
    dest_resolved = dest_dir.resolve()
    for member in tf.getmembers():
        member_path = (dest_resolved / member.name).resolve()
        if dest_resolved != member_path and dest_resolved not in member_path.parents:
            raise SystemExit(f"ERROR: unsafe path inside archive: {member.name}")
        if member.issym() or member.islnk():
            link_target = (member_path.parent / member.linkname).resolve()
            if dest_resolved != link_target and dest_resolved not in link_target.parents:
                raise SystemExit(f"ERROR: unsafe symlink target inside archive: {member.name}")
    if hasattr(tarfile, "data_filter"):
        tf.extractall(path=dest_resolved, filter="fully_trusted")
    else:
        tf.extractall(path=dest_resolved)


def cmd_decrypt(in_file_str: str, dest_dir_str: str) -> None:
    in_file = Path(in_file_str).resolve()
    dest_dir = Path(dest_dir_str).resolve()
    if not in_file.is_file():
        raise SystemExit(f"ERROR: encrypted file not found: {in_file}")
    raw = in_file.read_bytes()
    parts = raw.split(b"\n", 2)
    if len(parts) != 3 or parts[0] != b"R4ENC1":
        raise SystemExit("ERROR: invalid transit archive header")
    expected_tag = parts[1].decode("ascii", errors="strict")
    ciphertext = parts[2]
    enc_key, mac_key = derive_keys()
    actual_tag = hmac.new(mac_key, ciphertext, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected_tag, actual_tag):
        raise SystemExit("ERROR: transit archive HMAC verification failed (wrong run context or corrupted data)")

    dest_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="r4-dec-") as tmp:
        ct_path = Path(tmp) / "payload.ct"
        tar_path = Path(tmp) / "payload.tar.gz"
        ct_path.write_bytes(ciphertext)
        env = os.environ.copy()
        env["TRANSIT_ENC_KEY"] = enc_key
        subprocess.run(
            [
                "openssl", "enc", "-d", "-aes-256-cbc", "-md", "sha256",
                "-pbkdf2", "-iter", "200000",
                "-pass", "env:TRANSIT_ENC_KEY",
                "-in", str(ct_path), "-out", str(tar_path),
            ],
            env=env,
            check=True,
        )
        with tarfile.open(tar_path, mode="r:gz") as tf:
            safe_extract_tar(tf, dest_dir)


def parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, rhs = line.split("=", 1)
        key = key.strip()
        tokens = shlex.split(rhs, comments=True)
        values[key] = tokens[0] if len(tokens) == 1 else " ".join(tokens)
    return values


def cmd_load_env(env_file_str: str, export_gh: bool) -> None:
    env_path = Path(env_file_str).resolve()
    values = parse_env_file(env_path)
    to_mask: set[str] = set()
    for field in ("UPSTREAM_REPO", "DISPLAY_NAME", "ANDROID_REPO", "IOS_REPO"):
        val = values.get(field, "").strip()
        if len(val) >= 3:
            to_mask.add(val)
    for field in ("APP_PACKAGE_ID", "MASK_WORDS"):
        for token in values.get(field, "").replace(",", " ").split():
            if len(token) >= 3:
                to_mask.add(token)
    for item in sorted(to_mask):
        print(f"::add-mask::{item}", flush=True)

    exports_lines = []
    for k, v in sorted(values.items()):
        if "\n" in v:
            raise SystemExit(f"ERROR: multiline value in {k}")
        exports_lines.append(f"export {k}={shlex.quote(v)}")
    (env_path.parent / "exports.sh").write_text("\n".join(exports_lines) + "\n", encoding="utf-8")

    if export_gh:
        gh_env = os.environ.get("GITHUB_ENV")
        if not gh_env:
            raise SystemExit("ERROR: GITHUB_ENV is not set")
        with open(gh_env, "a", encoding="utf-8") as fh:
            for k, v in sorted(values.items()):
                fh.write(f"{k}={v}\n")


def cmd_purge_artifacts() -> None:
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    if not (token and repo and run_id):
        print("[cleanup] skipping artifact purge (missing GITHUB_TOKEN/GITHUB_REPOSITORY/GITHUB_RUN_ID)")
        return
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "auto-builds-transit-cleanup",
    }
    list_url = f"https://api.github.com/repos/{repo}/actions/runs/{run_id}/artifacts?per_page=100"
    req = urllib.request.Request(list_url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    deleted = 0
    for art in payload.get("artifacts", []):
        name = art.get("name", "")
        art_id = art.get("id")
        if not name.startswith("transit-") or art.get("expired"):
            continue
        del_url = f"https://api.github.com/repos/{repo}/actions/artifacts/{art_id}"
        del_req = urllib.request.Request(del_url, headers=headers, method="DELETE")
        try:
            with urllib.request.urlopen(del_req, timeout=30):
                deleted += 1
        except urllib.error.HTTPError as err:
            if err.code != 404:
                print(f"[cleanup] WARN: could not delete artifact {art_id}: HTTP {err.code}", file=sys.stderr)
    print(f"[cleanup] purged {deleted} temporary transit artifact(s)")


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: transit-crypto.sh <encrypt|decrypt|load-env|purge-artifacts> ...")
    sub = sys.argv[1]
    if sub == "encrypt":
        cmd_encrypt(sys.argv[2], sys.argv[3])
    elif sub == "decrypt":
        cmd_decrypt(sys.argv[2], sys.argv[3])
    elif sub == "load-env":
        cmd_load_env(sys.argv[2], "--export-github-env" in sys.argv[3:])
    elif sub == "purge-artifacts":
        cmd_purge_artifacts()
    else:
        raise SystemExit(f"ERROR: unknown subcommand {sub}")


if __name__ == "__main__":
    main()
PY
