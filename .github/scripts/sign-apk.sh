#!/usr/bin/env bash
# Strip any build-time placeholder signature, page-align (4-byte), sign with v1+v2+v3,
# and strictly enforce single-signer SHA-256 fingerprint + manifest package allowlist.
#
# Usage:
#   sign-apk.sh <input.apk> <output.apk> <keystore-file> [--expected-sha256 <64hex>] [--expected-package <allowlist>]

set -euo pipefail

IN_APK="${1:?usage: $0 <input.apk> <output.apk> <keystore> [--expected-sha256 <hex>] [--expected-package <pkgs>]}"
OUT_APK="${2:?}"
KEYSTORE_FILE="${3:?}"
shift 3

EXPECTED_SHA256=""
EXPECTED_PACKAGES=""

while [ $# -gt 0 ]; do
  case "$1" in
    --expected-sha256)
      EXPECTED_SHA256="${2:?}"
      shift 2
      ;;
    --expected-package)
      EXPECTED_PACKAGES="${2:-}"
      shift 2
      ;;
    *)
      echo "[sign-apk] ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

: "${ANDROID_HOME:=${ANDROID_SDK_ROOT:-}}"
if [ -z "${ANDROID_HOME}" ]; then
  echo "[sign-apk] ERROR: ANDROID_HOME/ANDROID_SDK_ROOT is not set" >&2
  exit 2
fi
if [ -z "${KEYSTORE_PASS:-}" ]; then
  echo "[sign-apk] ERROR: KEYSTORE_PASS must be set in env" >&2
  exit 2
fi
: "${KEY_PASS:=${KEYSTORE_PASS}}"
export KEYSTORE_PASS KEY_PASS

if [ -z "${KEY_ALIAS:-}" ]; then
  KEY_ALIAS="$(keytool -list -keystore "${KEYSTORE_FILE}" -storepass:env KEYSTORE_PASS 2>/dev/null |
    awk -F, '/PrivateKeyEntry/ {print $1}' | head -n 1 | tr -d ' \r')"
  if [ -z "${KEY_ALIAS}" ]; then
    echo "[sign-apk] ERROR: unable to discover PrivateKeyEntry alias in keystore" >&2
    exit 2
  fi
fi

BUILD_TOOLS="$(find "${ANDROID_HOME}/build-tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n 1)"
if [ -z "${BUILD_TOOLS}" ]; then
  echo "[sign-apk] ERROR: no build-tools found under ${ANDROID_HOME}" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

PY_BIN="python3"
command -v "${PY_BIN}" >/dev/null 2>&1 || PY_BIN="python"

"${PY_BIN}" - "${IN_APK}" "${TMP_DIR}/stripped.apk" <<'PY'
import fnmatch
import sys
import zipfile

src_apk, dst_apk = sys.argv[1], sys.argv[2]
SIG_PATTERNS = (
    "META-INF/*.SF",
    "META-INF/*.RSA",
    "META-INF/*.DSA",
    "META-INF/*.EC",
    "META-INF/MANIFEST.MF",
    "META-INF/SIG-*",
)

with zipfile.ZipFile(src_apk, "r") as zin, zipfile.ZipFile(dst_apk, "w") as zout:
    for item in zin.infolist():
        upper_name = item.filename.upper()
        if any(fnmatch.fnmatchcase(upper_name, pat) for pat in SIG_PATTERNS):
            continue
        data = zin.read(item.filename)
        cloned = zipfile.ZipInfo(filename=item.filename, date_time=item.date_time)
        cloned.compress_type = item.compress_type
        cloned.comment = item.comment
        cloned.extra = item.extra
        cloned.create_system = item.create_system
        cloned.external_attr = item.external_attr
        cloned.internal_attr = item.internal_attr
        cloned.flag_bits = item.flag_bits & ~0x08
        zout.writestr(cloned, data)
PY

"${BUILD_TOOLS}/zipalign" -f -p 4 "${TMP_DIR}/stripped.apk" "${TMP_DIR}/aligned.apk"
"${BUILD_TOOLS}/zipalign" -c 4 "${TMP_DIR}/aligned.apk"

mkdir -p "$(dirname "${OUT_APK}")"
"${BUILD_TOOLS}/apksigner" sign \
  --ks "${KEYSTORE_FILE}" \
  --ks-key-alias "${KEY_ALIAS}" \
  --ks-pass env:KEYSTORE_PASS \
  --key-pass env:KEY_PASS \
  --v1-signing-enabled true \
  --v2-signing-enabled true \
  --v3-signing-enabled true \
  --out "${OUT_APK}" \
  "${TMP_DIR}/aligned.apk"

VERIFY_OUT="$("${BUILD_TOOLS}/apksigner" verify --verbose --print-certs "${OUT_APK}" 2>&1)"
if printf '%s\n' "${VERIFY_OUT}" | grep -Fq 'Signer #2'; then
  echo "[sign-apk] ERROR: unexpected multiple signers (Signer #2 detected)" >&2
  exit 1
fi
SIGNER_COUNT_LINE="$(printf '%s\n' "${VERIFY_OUT}" | sed -nE 's/^Number of signers:[[:space:]]*([0-9]+).*$/\1/p' | head -n 1)"
if [ -n "${SIGNER_COUNT_LINE}" ] && [ "${SIGNER_COUNT_LINE}" != "1" ]; then
  echo "[sign-apk] ERROR: expected Number of signers == 1, got ${SIGNER_COUNT_LINE}" >&2
  exit 1
fi

UNIQUE_DIGESTS="$(
  printf '%s\n' "${VERIFY_OUT}" \
    | sed -nE 's/^.*certificate SHA-256 digest:[[:space:]]*//p' \
    | tr -d ': \r\t' \
    | tr '[:upper:]' '[:lower:]' \
    | grep -E '.+' \
    | sort -u
)"
UNIQUE_COUNT="$(printf '%s\n' "${UNIQUE_DIGESTS}" | grep -Ec '^[0-9a-f]{64}$' || true)"
if [ "${UNIQUE_COUNT}" -ne 1 ]; then
  echo "[sign-apk] ERROR: expected exactly 1 unique 64-hex signer SHA-256 digest, got:" >&2
  printf '%s\n' "${VERIFY_OUT}" >&2
  exit 1
fi
ACTUAL_SHA256="$(printf '%s\n' "${UNIQUE_DIGESTS}" | head -n 1)"

if [ -n "${EXPECTED_SHA256}" ]; then
  NORM_EXPECTED="$(printf '%s' "${EXPECTED_SHA256}" | tr -d ': \r\t' | tr '[:upper:]' '[:lower:]')"
  if [ "${ACTUAL_SHA256}" != "${NORM_EXPECTED}" ]; then
    echo "[sign-apk] ERROR: certificate SHA-256 mismatch! expected=${NORM_EXPECTED} actual=${ACTUAL_SHA256}" >&2
    exit 1
  fi
fi

# Verify embedded provenance.json signer_sha256 if present inside the APK
PROV_SIGNER="$("${PY_BIN}" - "${OUT_APK}" <<'PY'
import json
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "r") as zf:
    if "assets/provenance.json" in zf.namelist():
        data = json.loads(zf.read("assets/provenance.json").decode("utf-8"))
        print(data.get("signer_sha256", ""))
PY
)"
if [ -n "${PROV_SIGNER}" ] && [ "${PROV_SIGNER}" != "${ACTUAL_SHA256}" ]; then
  echo "[sign-apk] ERROR: provenance.json signer_sha256 (${PROV_SIGNER}) != APK signer (${ACTUAL_SHA256})" >&2
  exit 1
fi

if [ -n "${EXPECTED_PACKAGES}" ]; then
  APKANALYZER_BIN="$(command -v apkanalyzer || true)"
  if [ -z "${APKANALYZER_BIN}" ] && [ -d "${ANDROID_HOME}/cmdline-tools" ]; then
    APKANALYZER_BIN="$(find "${ANDROID_HOME}/cmdline-tools" -type f -path '*/bin/apkanalyzer' 2>/dev/null | sort -V | tail -n 1 || true)"
  fi
  if [ -z "${APKANALYZER_BIN}" ] || [ ! -x "${APKANALYZER_BIN}" ]; then
    echo "[sign-apk] ERROR: apkanalyzer not found for manifest package verification" >&2
    exit 1
  fi
  ACTUAL_PKG="$("${APKANALYZER_BIN}" manifest application-id "${OUT_APK}" | tr -d '\r\n ')"
  pkg_ok=false
  for allowed in ${EXPECTED_PACKAGES//,/ }; do
    if [ "${ACTUAL_PKG}" = "${allowed}" ]; then
      pkg_ok=true
      break
    fi
  done
  if [ "${pkg_ok}" != true ]; then
    echo "[sign-apk] ERROR: manifest application-id '${ACTUAL_PKG}' not in allowed set (${EXPECTED_PACKAGES})" >&2
    exit 1
  fi
fi

echo "[sign-apk] verified single-signer APK: ${OUT_APK} (sha256=${ACTUAL_SHA256})"
