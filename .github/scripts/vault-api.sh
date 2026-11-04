#!/usr/bin/env bash
# Private vault coordinator: version resolution, patch idempotence precheck,
# deduplicated private Issue reporting, and Draft Release asset management.
#
# Subcommands:
#   vault-api.sh prepare <target-id>
#   vault-api.sh report-issue <target-id> <summary> <log-file>
#   vault-api.sh publish-release <resolved-env> <notes-file> <assets-dir>

set -euo pipefail

PY_BIN="python3"
command -v "${PY_BIN}" >/dev/null 2>&1 || PY_BIN="python"

"${PY_BIN}" - "$@" <<'PY'
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

MAX_ASSET_BYTES = 2147483648  # 2 GiB GitHub Release single-asset limit


def mask(value: str) -> None:
    val = value.strip()
    if len(val) >= 3:
        print(f"::add-mask::{val}", flush=True)


def parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, rhs = line.split("=", 1)
        tokens = shlex.split(rhs, comments=True)
        values[key.strip()] = tokens[0] if len(tokens) == 1 else " ".join(tokens)
    return values


def gh_request(
    method: str,
    url: str,
    token: str | None = None,
    data: bytes | dict | None = None,
    content_type: str = "application/json",
    allow_404: bool = False,
    retries: int = 3,
):
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "auto-builds-vault-coordinator",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = None
    if isinstance(data, dict):
        body = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = content_type
    elif isinstance(data, bytes):
        body = data
        headers["Content-Type"] = content_type
        headers["Content-Length"] = str(len(body))

    last_err = None
    for attempt in range(retries):
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                raw = resp.read()
                return json.loads(raw.decode("utf-8")) if raw else {}
        except urllib.error.HTTPError as err:
            if err.code == 404 and allow_404:
                return None
            last_err = err
            if err.code in (429, 500, 502, 503, 504) and attempt + 1 < retries:
                time.sleep(2 ** (attempt + 1))
                continue
            detail = err.read().decode("utf-8", errors="replace")[:400]
            raise RuntimeError(f"GitHub API {method} {url} failed with HTTP {err.code}: {detail}") from err
        except urllib.error.URLError as err:
            last_err = err
            if attempt + 1 < retries:
                time.sleep(2 ** (attempt + 1))
                continue
            raise RuntimeError(f"Network error calling {url}: {err}") from err
    raise RuntimeError(f"Exhausted retries for {url}: {last_err}")


def semver_tuple(ver: str) -> tuple[int, ...]:
    clean = ver.strip().removeprefix("v").split("-", 1)[0]
    parts = clean.split(".")
    if not all(p.isdigit() for p in parts):
        return (0,)
    return tuple(int(p) for p in parts)


def clone_vault(vault_repo: str, vault_token: str, dest: Path) -> None:
    mask(vault_repo)
    if dest.exists():
        shutil.rmtree(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    basic = base64.b64encode(f"x-access-token:{vault_token}".encode("utf-8")).decode("ascii")
    mask(basic)
    subprocess.run(
        [
            "git",
            "-c",
            f"http.https://github.com/.extraheader=AUTHORIZATION: basic {basic}",
            "clone",
            "-q",
            "--depth=1",
            f"https://github.com/{vault_repo}.git",
            str(dest),
        ],
        check=True,
    )


def peel_remote_ref(repo_url: str, ref_input: str) -> str:
    if re.fullmatch(r"[0-9a-f]{40}", ref_input):
        return ref_input
    queries = (
        [ref_input]
        if ref_input == "HEAD" or ref_input.startswith("refs/")
        else [f"refs/tags/{ref_input}^{{}}", f"refs/tags/{ref_input}", f"refs/heads/{ref_input}"]
    )
    out = subprocess.check_output(
        ["git", "ls-remote", repo_url, *queries], text=True
    ).strip()
    if not out:
        raise RuntimeError(f"Unable to resolve upstream ref {ref_input!r}")
    lines = [ln.split() for ln in out.splitlines() if ln.strip()]
    for sha, rname in lines:
        if rname.endswith("^{}") and re.fullmatch(r"[0-9a-f]{40}", sha):
            return sha
    sha = lines[0][0]
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise RuntimeError(f"Invalid resolved commit SHA: {sha}")
    return sha


def resolve_upstream(cfg: dict[str, str], force_ref: str, public_token: str) -> tuple[str, str]:
    upstream_repo = cfg["UPSTREAM_REPO"]
    repo_url = f"https://github.com/{upstream_repo}.git"
    if force_ref:
        sha = peel_remote_ref(repo_url, force_ref)
        if re.fullmatch(r"[0-9a-f]{40}", force_ref):
            tag = f"{cfg.get('PINNED_TAG', 'manual')}-{sha[:8]}"
        elif force_ref == "HEAD":
            tag = f"head-{sha[:8]}"
        else:
            tag = force_ref.removeprefix("refs/tags/").removeprefix("refs/heads/").replace("/", "-")
        return tag, sha

    tag_regex = re.compile(cfg.get("TAG_REGEX", r"^v?[0-9]+\.[0-9]+\.[0-9]+$"))
    candidate_tag = ""
    rel = gh_request(
        "GET",
        f"https://api.github.com/repos/{upstream_repo}/releases/latest",
        token=public_token or None,
        allow_404=True,
    )
    if rel and isinstance(rel.get("tag_name"), str):
        t = rel["tag_name"].strip()
        if tag_regex.fullmatch(t):
            candidate_tag = t

    if not candidate_tag:
        raw_tags = subprocess.check_output(
            ["git", "ls-remote", "--tags", "--refs", repo_url], text=True
        )
        matched = []
        for line in raw_tags.splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[1].startswith("refs/tags/"):
                t = parts[1].removeprefix("refs/tags/")
                if tag_regex.fullmatch(t):
                    matched.append(t)
        if matched:
            if all(re.match(r"^v?[0-9]+\.", x) for x in matched):
                matched.sort(key=semver_tuple)
            else:
                matched.sort()
            candidate_tag = matched[-1]

    min_ver = cfg.get("MIN_VERSION", "")
    min_tag = cfg.get("MIN_TAG", "")
    if candidate_tag:
        if min_ver and semver_tuple(candidate_tag) < semver_tuple(min_ver):
            candidate_tag = ""
        elif min_tag and candidate_tag < min_tag:
            candidate_tag = ""

    if candidate_tag:
        pinned_tag = cfg.get("PINNED_TAG", "")
        pinned_sha = cfg.get("PINNED_SHA", "")
        if candidate_tag == pinned_tag and re.fullmatch(r"[0-9a-f]{40}", pinned_sha):
            return candidate_tag, pinned_sha
        return candidate_tag, peel_remote_ref(repo_url, candidate_tag)

    if cfg.get("TRACK_MODE") == "release_or_pinned":
        pinned_sha = cfg.get("PINNED_SHA", "")
        pinned_tag = cfg.get("PINNED_TAG", "")
        if re.fullmatch(r"[0-9a-f]{40}", pinned_sha) and pinned_tag:
            return pinned_tag, pinned_sha

    raise RuntimeError("Could not determine a valid upstream release or pinned commit")


def upsert_private_issue(vault_repo: str, vault_token: str, target_id: str, summary: str, detail: str) -> None:
    title = f"[Precheck] {target_id}: {summary}"
    issues = gh_request(
        "GET",
        f"https://api.github.com/repos/{vault_repo}/issues?state=open&per_page=50",
        token=vault_token,
    )
    run_url = (
        f"https://github.com/{os.environ.get('GITHUB_REPOSITORY', '')}/actions/runs/"
        f"{os.environ.get('GITHUB_RUN_ID', '')}"
    )
    body = (
        f"Automated precheck alert for target `{target_id}`.\n\n"
        f"- Summary: {summary}\n"
        f"- Workflow run: {run_url}\n\n"
        f"```text\n{detail[-3500:]}\n```\n"
    )
    existing = next((i for i in issues if "pull_request" not in i and i.get("title") == title), None)
    if existing:
        gh_request(
            "POST",
            f"https://api.github.com/repos/{vault_repo}/issues/{existing['number']}/comments",
            token=vault_token,
            data={"body": body},
        )
        print(f"[vault] updated existing private alert issue #{existing['number']}")
    else:
        created = gh_request(
            "POST",
            f"https://api.github.com/repos/{vault_repo}/issues",
            token=vault_token,
            data={"title": title, "body": body},
        )
        print(f"[vault] opened private alert issue #{created.get('number')}")


def clean_starter_assets(vault_repo: str, vault_token: str, release: dict) -> list[dict]:
    healthy = []
    for asset in release.get("assets", []):
        if asset.get("state") == "starter":
            gh_request(
                "DELETE",
                f"https://api.github.com/repos/{vault_repo}/releases/assets/{asset['id']}",
                token=vault_token,
                allow_404=True,
            )
        else:
            healthy.append(asset)
    return healthy


def find_or_create_draft(
    vault_repo: str, vault_token: str, release_tag: str, title: str, body: str
) -> dict:
    enc_tag = urllib.parse.quote(release_tag, safe="")
    rel = gh_request(
        "GET",
        f"https://api.github.com/repos/{vault_repo}/releases/tags/{enc_tag}",
        token=vault_token,
        allow_404=True,
    )
    if rel:
        clean_starter_assets(vault_repo, vault_token, rel)
        return rel

    # Draft releases do not have a git tag ref yet, so scan recent releases by tag_name/name.
    releases = gh_request(
        "GET",
        f"https://api.github.com/repos/{vault_repo}/releases?per_page=50",
        token=vault_token,
    )
    for item in releases:
        if item.get("draft") and item.get("tag_name") == release_tag:
            clean_starter_assets(vault_repo, vault_token, item)
            return item

    return gh_request(
        "POST",
        f"https://api.github.com/repos/{vault_repo}/releases",
        token=vault_token,
        data={
            "tag_name": release_tag,
            "name": title,
            "body": body,
            "draft": True,
            "prerelease": False,
        },
    )


def write_gh_output(pairs: dict[str, str]) -> None:
    out_path = os.environ.get("GITHUB_OUTPUT")
    if not out_path:
        return
    with open(out_path, "a", encoding="utf-8") as fh:
        for k, v in pairs.items():
            fh.write(f"{k}={v}\n")


def cmd_prepare(target_id: str) -> None:
    vault_repo = os.environ["VAULT_REPO"].strip()
    vault_token = os.environ["VAULT_TOKEN"].strip()
    public_token = os.environ.get("GITHUB_TOKEN", "").strip()
    force_ref = os.environ.get("FORCE_REF", "").strip()
    platforms = os.environ.get("PLATFORMS", "all").strip()
    publish_release = os.environ.get("PUBLISH_RELEASE", "true").lower() == "true"
    event_name = os.environ.get("GITHUB_EVENT_NAME", "")

    runner_temp = Path(os.environ.get("RUNNER_TEMP", "/tmp")).resolve()
    vault_dir = runner_temp / "vault"
    clone_vault(vault_repo, vault_token, vault_dir)

    target_dir = vault_dir / target_id
    cfg = parse_env_file(target_dir / "source.env")
    for field in ("UPSTREAM_REPO", "DISPLAY_NAME", "ANDROID_REPO", "IOS_REPO"):
        if cfg.get(field):
            mask(cfg[field])
    for field in ("APP_PACKAGE_ID", "MASK_WORDS"):
        for w in cfg.get(field, "").replace(",", " ").split():
            mask(w)

    upstream_tag, upstream_sha = resolve_upstream(cfg, force_ref, public_token)
    release_tag = f"{target_id}-{upstream_tag}"

    enc_tag = urllib.parse.quote(release_tag, safe="")
    existing_rel = gh_request(
        "GET",
        f"https://api.github.com/repos/{vault_repo}/releases/tags/{enc_tag}",
        token=vault_token,
        allow_404=True,
    )
    if existing_rel and not existing_rel.get("draft") and event_name == "schedule" and not force_ref:
        print(f"[vault] release {release_tag} already published; skipping scheduled build")
        write_gh_output({"should_skip": "true", "release_tag": release_tag, "upstream_sha": upstream_sha})
        return

    # 1. Run private vault unit test suite
    subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", str(vault_dir / "tests"), "-v"],
        check=True,
    )

    # 2. Fetch pinned SHA + two-pass binary diff idempotence precheck
    precheck_src = runner_temp / "precheck-src"
    try:
        proc = subprocess.run(
            [
                "bash",
                str(vault_dir / "scripts/prepare-upstream.sh"),
                str(target_dir),
                str(precheck_src),
                "--sha",
                upstream_sha,
                "--tag",
                upstream_tag,
                "--verify-idempotent",
            ],
            text=True,
            capture_output=True,
            check=True,
        )
        print(proc.stdout, end="")

        android_sha = ""
        android_resolver = target_dir / "scripts/resolve-android-ref.py"
        if android_resolver.is_file() and ("all" in platforms or "android" in platforms):
            res_proc = subprocess.run(
                [
                    sys.executable,
                    str(android_resolver),
                    upstream_tag,
                    "--repository",
                    f"https://github.com/{cfg['ANDROID_REPO']}.git",
                ],
                text=True,
                capture_output=True,
                check=True,
            )
            android_sha = res_proc.stdout.strip()

        flag_verifier = target_dir / "scripts/verify-build-flags.py"
        if flag_verifier.is_file():
            subprocess.run(
                [sys.executable, str(flag_verifier), str(precheck_src)],
                text=True,
                capture_output=True,
                check=True,
            )
    except subprocess.CalledProcessError as err:
        combined = (err.stdout or "") + "\n" + (err.stderr or "")
        print(combined, file=sys.stderr)
        upsert_private_issue(
            vault_repo,
            vault_token,
            target_id,
            f"patch/ref precheck failed at {upstream_tag} ({upstream_sha[:8]})",
            combined,
        )
        raise SystemExit(1)

    # 3. Create clean patched source archive before any compiler touches the tree
    src_out = runner_temp / "src-out"
    if src_out.exists():
        shutil.rmtree(src_out)
    src_out.mkdir(parents=True)
    src_tar_name = f"{cfg['DISPLAY_NAME']}-{upstream_tag}-source.tar.gz"
    subprocess.run(
        [
            "bash",
            str(vault_dir / "scripts/make-source-tarball.sh"),
            str(precheck_src),
            str(src_out / src_tar_name),
        ],
        check=True,
    )

    # 4. Prepare Draft Release in private vault when publishing is enabled
    release_id = ""
    if publish_release:
        notes_text = (target_dir / "notes.md").read_text(encoding="utf-8")
        draft = find_or_create_draft(
            vault_repo,
            vault_token,
            release_tag,
            f"{cfg['DISPLAY_NAME']} {upstream_tag}",
            notes_text,
        )
        release_id = str(draft["id"])

    # 5. Stage transit kit
    kit_dir = runner_temp / "kit"
    if kit_dir.exists():
        shutil.rmtree(kit_dir)
    shutil.copytree(vault_dir / "scripts", kit_dir / "scripts")
    shutil.copytree(target_dir, kit_dir / "target")

    resolved = dict(cfg)
    resolved.update(
        {
            "TARGET_ID": target_id,
            "UPSTREAM_TAG": upstream_tag,
            "UPSTREAM_SHA": upstream_sha,
            "UPSTREAM_URL": f"https://github.com/{cfg['UPSTREAM_REPO']}.git",
            "ANDROID_SHA": android_sha,
            "RELEASE_TAG": release_tag,
            "RELEASE_ID": release_id,
        }
    )
    lines = [f"{k}={shlex.quote(str(v))}" for k, v in sorted(resolved.items())]
    (kit_dir / "resolved.env").write_text("\n".join(lines) + "\n", encoding="utf-8")

    write_gh_output(
        {
            "should_skip": "false",
            "target_id": target_id,
            "upstream_tag": upstream_tag,
            "upstream_sha": upstream_sha,
            "release_tag": release_tag,
        }
    )
    print(f"[vault] prepared target={target_id} release_tag={release_tag} sha={upstream_sha[:12]}")


def cmd_report_issue(target_id: str, summary: str, log_file_str: str) -> None:
    vault_repo = os.environ["VAULT_REPO"].strip()
    vault_token = os.environ["VAULT_TOKEN"].strip()
    mask(vault_repo)
    detail = Path(log_file_str).read_text(encoding="utf-8", errors="replace")
    upsert_private_issue(vault_repo, vault_token, target_id, summary, detail)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def cmd_publish_release(resolved_env_str: str, notes_file_str: str, assets_dir_str: str) -> None:
    vault_repo = os.environ["VAULT_REPO"].strip()
    vault_token = os.environ["VAULT_TOKEN"].strip()
    mask(vault_repo)

    cfg = parse_env_file(Path(resolved_env_str))
    for field in ("UPSTREAM_REPO", "DISPLAY_NAME", "ANDROID_REPO", "IOS_REPO"):
        if cfg.get(field):
            mask(cfg[field])
    for field in ("APP_PACKAGE_ID", "MASK_WORDS"):
        for w in cfg.get(field, "").replace(",", " ").split():
            mask(w)

    release_tag = cfg["RELEASE_TAG"]
    notes_body = Path(notes_file_str).read_text(encoding="utf-8")
    provenance_footer = (
        f"\n\n---\n"
        f"- Tag: `{cfg['UPSTREAM_TAG']}`\n"
        f"- Commit: `{cfg['UPSTREAM_SHA']}`\n"
    )
    if cfg.get("EXPECTED_SIGNER_SHA256"):
        provenance_footer += f"- Android Signer SHA-256: `{cfg['EXPECTED_SIGNER_SHA256']}`\n"

    rel = find_or_create_draft(
        vault_repo,
        vault_token,
        release_tag,
        f"{cfg['DISPLAY_NAME']} {cfg['UPSTREAM_TAG']}",
        notes_body + provenance_footer,
    )
    rel_id = rel["id"]
    is_draft = bool(rel.get("draft"))
    existing_assets = {a["name"]: a for a in clean_starter_assets(vault_repo, vault_token, rel)}

    assets_dir = Path(assets_dir_str).resolve()
    files = sorted(p for p in assets_dir.iterdir() if p.is_file())
    if not files:
        raise SystemExit("ERROR: no release assets found to publish")

    for fpath in files:
        size = fpath.stat().st_size
        if size <= 0 or size >= MAX_ASSET_BYTES:
            raise SystemExit(f"ERROR: invalid asset size for {fpath.name}: {size} bytes")
        digest = sha256_file(fpath)
        if fpath.name in existing_assets:
            remote = existing_assets[fpath.name]
            remote_digest = (remote.get("digest") or "").removeprefix("sha256:")
            if remote_digest and remote_digest == digest and remote.get("state") == "uploaded":
                print(f"[publish] reusing identical uploaded asset: {fpath.name}")
                continue
            if is_draft:
                gh_request(
                    "DELETE",
                    f"https://api.github.com/repos/{vault_repo}/releases/assets/{remote['id']}",
                    token=vault_token,
                    allow_404=True,
                )
            else:
                raise SystemExit(
                    f"ERROR: published release {release_tag} already has differing asset {fpath.name}"
                )

        upload_url = (
            f"https://uploads.github.com/repos/{vault_repo}/releases/{rel_id}/assets?"
            f"{urllib.parse.urlencode({'name': fpath.name})}"
        )
        uploaded = gh_request(
            "POST",
            upload_url,
            token=vault_token,
            data=fpath.read_bytes(),
            content_type="application/octet-stream",
            retries=3,
        )
        if uploaded.get("state") != "uploaded":
            raise SystemExit(f"ERROR: asset {fpath.name} did not reach uploaded state")
        print(f"[publish] uploaded {fpath.name} ({size} bytes)")

    gh_request(
        "PATCH",
        f"https://api.github.com/repos/{vault_repo}/releases/{rel_id}",
        token=vault_token,
        data={
            "name": f"{cfg['DISPLAY_NAME']} {cfg['UPSTREAM_TAG']}",
            "body": notes_body + provenance_footer,
            "draft": False,
        },
    )
    print(f"[publish] finalized private release {release_tag}")


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: vault-api.sh <prepare|report-issue|publish-release> ...")
    sub = sys.argv[1]
    if sub == "prepare":
        cmd_prepare(sys.argv[2])
    elif sub == "report-issue":
        cmd_report_issue(sys.argv[2], sys.argv[3], sys.argv[4])
    elif sub == "publish-release":
        cmd_publish_release(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        raise SystemExit(f"ERROR: unknown subcommand {sub}")


if __name__ == "__main__":
    main()
PY
