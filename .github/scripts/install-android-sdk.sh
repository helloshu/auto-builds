#!/usr/bin/env bash
# Install Android SDK/NDK components directly via preinstalled sdkmanager.

set -euo pipefail

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "${SDK}" ]; then
  echo "[android-sdk] ERROR: ANDROID_HOME/ANDROID_SDK_ROOT is not set" >&2
  exit 2
fi

SDKM="$(find "${SDK}/cmdline-tools" -type f -path '*/bin/sdkmanager' 2>/dev/null | sort -V | tail -n 1 || true)"
if [ -z "${SDKM}" ] || [ ! -x "${SDKM}" ]; then
  SDKM="$(command -v sdkmanager || true)"
fi
if [ -z "${SDKM}" ]; then
  echo "[android-sdk] ERROR: sdkmanager not found under ${SDK}" >&2
  exit 2
fi

yes | "${SDKM}" --licenses > /dev/null 2>&1 || true

install_pkg() {
  local pkg="$1"
  local extra
  for extra in "" "--channel=3" "--channel=2 --include_obsolete"; do
    # shellcheck disable=SC2086
    if "${SDKM}" --install ${extra} "${pkg}" > /tmp/sdk-install.log 2>&1; then
      echo "[android-sdk] installed ${pkg} ${extra:-(stable)}"
      return 0
    fi
  done
  tail -n 10 /tmp/sdk-install.log >&2 || true
  return 1
}

for pkg in "$@"; do
  if ! install_pkg "${pkg}"; then
    case "${pkg}" in
      platforms\;android-[0-9]*) install_pkg "${pkg}.0" ;;
      *) exit 1 ;;
    esac
  fi
  case "${pkg}" in
    ndk\;*)
      ndk_ver="${pkg#ndk;}"
      if [ -n "${GITHUB_ENV:-}" ]; then
        {
          echo "ANDROID_NDK_HOME=${SDK}/ndk/${ndk_ver}"
          echo "ANDROID_NDK_ROOT=${SDK}/ndk/${ndk_ver}"
        } >> "${GITHUB_ENV}"
      fi
      ;;
  esac
done
