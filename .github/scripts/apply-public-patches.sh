#!/usr/bin/env bash
# Deterministic strict security patch selector for public workflows.
#
# Usage:
#   apply-public-patches.sh <patch-dir> <src-dir> <upstream-tag>
#
# Candidate resolution order for each `<name>.patch` in `<patch-dir>`:
#   1. `<patch-dir>/versions/<upstream-tag>/<name>.patch` (exact tag override)
#   2. `<patch-dir>/<name>.patch`                         (default patch)
#   3. `<patch-dir>/versions/*/<name>.patch`              (newest-first fallback)
#
# All candidates are verified with strict `git apply --check` (zero fuzz) so
# security hunks can never drift silently.

set -euo pipefail

PATCH_DIR="${1:?usage: $0 <patch-dir> <src-dir> <upstream-tag>}"
SRC_DIR="${2:?}"
UPSTREAM_TAG="${3:?}"

PATCH_DIR="$(cd "${PATCH_DIR}" && pwd)"
SRC_DIR="$(cd "${SRC_DIR}" && pwd)"

shopt -s nullglob
BASE_PATCHES=("${PATCH_DIR}"/*.patch)
if [ "${#BASE_PATCHES[@]}" -eq 0 ]; then
  echo "::error::No security patches found under ${PATCH_DIR}" >&2
  exit 1
fi

for base_patch in "${BASE_PATCHES[@]}"; do
  patch_name="$(basename "${base_patch}")"
  candidates=()
  seen="|"

  exact_cand="${PATCH_DIR}/versions/${UPSTREAM_TAG}/${patch_name}"
  if [ -f "${exact_cand}" ]; then
    candidates+=("${exact_cand}")
    seen="${seen}${exact_cand}|"
  fi

  candidates+=("${base_patch}")
  seen="${seen}${base_patch}|"

  if [ -d "${PATCH_DIR}/versions" ]; then
    PY_BIN="python3"
    command -v "${PY_BIN}" >/dev/null 2>&1 || PY_BIN="python"
    while IFS= read -r rel_cand; do
      rel_cand="${rel_cand%$'\r'}"
      [ -n "${rel_cand}" ] || continue
      alt_cand="${PATCH_DIR}/${rel_cand}"
      if [[ "${seen}" != *"|${alt_cand}|"* ]]; then
        candidates+=("${alt_cand}")
        seen="${seen}${alt_cand}|"
      fi
    done < <("${PY_BIN}" - "${PATCH_DIR}/versions" "${patch_name}" "${UPSTREAM_TAG}" <<'PY'
from pathlib import Path
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(newline="\n")

ver_root = Path(sys.argv[1])
patch_name = sys.argv[2]
target_tag = sys.argv[3].strip()

def semver_key(tag: str):
    clean = tag.strip().removeprefix("v")
    base, _, pre = clean.partition("-")
    nums = tuple(int(x) if x.isdigit() else 0 for x in re.split(r"[^0-9]+", base) if x != "")
    pre_rank = 1 if not pre else 0
    pre_parts = tuple((0, int(p)) if p.isdigit() else (1, p) for p in pre.split(".")) if pre else ()
    return (nums, pre_rank, pre_parts, tag)

items = []
for d in ver_root.iterdir():
    cand = d / patch_name
    if d.is_dir() and cand.is_file():
        items.append((semver_key(d.name), f"versions/{d.name}/{patch_name}"))

tkey = semver_key(target_tag)
le = sorted([x for x in items if x[0][0] <= tkey[0]], key=lambda x: x[0], reverse=True)
gt = sorted([x for x in items if x[0][0] > tkey[0]], key=lambda x: x[0], reverse=True)
for _, rel_path in le + gt:
    sys.stdout.write(f"{rel_path}\n")
PY
    )
  fi

  applied=""
  diag=""
  for cand in "${candidates[@]}"; do
    rel_cand="${cand#"${PATCH_DIR}/"}"
    if err_out="$(git -C "${SRC_DIR}" apply --check "${cand}" 2>&1)"; then
      git -C "${SRC_DIR}" apply "${cand}"
      applied="${rel_cand}"
      echo "[patches] applied ${patch_name} (${applied}) for ${UPSTREAM_TAG}"
      break
    else
      diag="${diag}"$'\n'"  candidate ${rel_cand}: ${err_out}"
    fi
  done

  if [ -z "${applied}" ]; then
    echo "::error::Security patch ${patch_name} is incompatible with upstream ${UPSTREAM_TAG}:${diag}" >&2
    exit 1
  fi
done
