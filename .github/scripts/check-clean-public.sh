#!/usr/bin/env bash
# Zero-plaintext public repository hygiene guard:
# Hashes every lowercase identifier token across tracked/staged/untracked files
# (and optional commit-msg file) against SHA-256 digests of forbidden private keywords.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

PY_BIN="python3"
command -v "${PY_BIN}" >/dev/null 2>&1 || PY_BIN="python"

"${PY_BIN}" - "$@" <<'PY'
import hashlib
from pathlib import Path
import re
import subprocess
import sys

BASELINE_SHA = "0e701f449d959416a1d84a830308343a1b8dfd42"

# SHA-256 digests of forbidden lowercase words (no plaintext sensitive terms in public repo)
FORBIDDEN_TOKEN_SHA256 = {
    "779f5ecdf3b6e4efd7cb3e3adf3683461358b72854117151e33d4ce8ff81badb",
    "ff72a3ca0097d2ec2888d52f4a024f2465c0e9ae8af08f6604c17c9ce0307d17",
    "2024c973b95f97975fada6baa211fd370e9293fa317137b214372fd7794b3992",
    "bde70282b4409b87e4681622b0872cb58f1a6e79dce1a74d9fe3cb2c76d894d2",
    "5aa83b038f1288734bbc9a80e1ba82101781ada054e41b662409814a12050521",
    "be68c3b152e0c8e2882ad65fe077c1751c45302131f934bad830e0850d51fadd",
    "0c9819cbef0e9bce4443146721556be3ac6df7988037907676c058d31257c7be",
    "962234f6a7e9a213728dac8d016566ccddf7d0604b49b1a3e472de33024b43f1",
    "e50e196fa5b398a6455f53463e6c830caf84c6afbd3e96f9208b3c7f557bfc2d",
    "f8ff49dc0ad0c3af7f6a3b1cd78425ef9cccb94f5f9c4994023746a32f6f6dd7",
    "07aaca04e1eb85427ad5f2e983fc734073f8395e78ff3f353b5d4bcea481e3e4",
    "a51f62f55ed55266448e1c2820a79535dc1edfb28bd90cb7fcb1de343ba41ef2",
    "37600b30059dfc4844dd5470052567de3d8aaa12582d687ec857f0573e38caff",
    "157176d6be75485161f3b09d506f96e28840a781bca39da2cd36b7350c7811ff",
    "ebc19189604a5d14943c9e0a3f7899487f37d041cf4fd55e1b05426e38a77646",
    "3f5e3792011fe113257dab2830dba2edf0dde4a4bc3e0311149a054445207829",
    "184f35678d8c2e6a3ac2ef241a77f5abddcdb2559433256678de819fab98f1d6",
    "1eb0027e8bce2de313d10d481ee9808264fb17e96d55228d066f8fccb1281f25",
    "38d0bbee4973f1b6cf99aaf02f12a4e64ccf6c6e8d14ca68dbe6b4c2cff918d2",
    "590d11d79ad65f8cabd0c2d129d8dd7e660040bbc9198b422415b4b4fc42ebf5",
    "f326395de2edff401a454ca12ddc4a1b65f2170a4c28a000812624c5ff7b4ae5",
    "090bb0fbea66b20a17d6a2a3808340ba7628d167e3b6786655fc694cb9b4bc22",
}

TOKEN_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]*")
SUBTOKEN_RE = re.compile(r"[A-Za-z0-9]+")


def scan_text(label: str, text: str) -> list[str]:
    violations: list[str] = []
    for lineno, line in enumerate(text.splitlines(), 1):
        candidates = set()
        for tok in TOKEN_RE.findall(line):
            candidates.add(tok.lower())
        for tok in SUBTOKEN_RE.findall(line):
            candidates.add(tok.lower())
        for cand in candidates:
            digest = hashlib.sha256(cand.encode("utf-8")).hexdigest()
            if digest in FORBIDDEN_TOKEN_SHA256:
                violations.append(f"{label}:{lineno}: forbidden token matched (sha256={digest[:12]}...)")
    return violations


def main() -> int:
    # Mode 1: commit-msg hook passes path to COMMIT_EDITMSG via --commit-msg <file>
    if len(sys.argv) >= 3 and sys.argv[1] == "--commit-msg":
        msg_path = Path(sys.argv[2])
        errs = scan_text(str(msg_path), msg_path.read_text(encoding="utf-8", errors="replace"))
        if errs:
            print("\n".join(errs), file=sys.stderr)
            return 1
        return 0

    # Collect all tracked, staged, and untracked files in public repository
    paths: set[str] = set()
    tracked = subprocess.check_output(["git", "ls-files"], text=True)
    paths.update(p for p in tracked.splitlines() if p)
    staged = subprocess.check_output(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"], text=True
    )
    paths.update(p for p in staged.splitlines() if p)
    untracked = subprocess.check_output(
        ["git", "ls-files", "--others", "--exclude-standard"], text=True
    )
    paths.update(p for p in untracked.splitlines() if p)

    all_errors: list[str] = []
    for rel in sorted(paths):
        all_errors.extend(scan_text(f"path:{rel}", rel))
        p = Path(rel)
        if p.is_file():
            content = p.read_text(encoding="utf-8", errors="ignore")
            all_errors.extend(scan_text(rel, content))

    if all_errors:
        print("\n".join(all_errors), file=sys.stderr)
        return 1

    print(f"[clean-check] verified {len(paths)} public file(s): 0 sensitive tokens")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
