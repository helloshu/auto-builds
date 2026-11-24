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
    while IFS= read -r ver_dir; do
      [ -n "${ver_dir}" ] || continue
      alt_cand="${PATCH_DIR}/versions/${ver_dir}/${patch_name}"
      if [ -f "${alt_cand}" ] && [[ "${seen}" != *"|${alt_cand}|"* ]]; then
        candidates+=("${alt_cand}")
        seen="${seen}${alt_cand}|"
      fi
    done < <(find "${PATCH_DIR}/versions" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort -V -r)
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
