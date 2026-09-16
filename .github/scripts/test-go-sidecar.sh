#!/usr/bin/env bash

set -euo pipefail

readonly max_attempts=3
readonly log_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"

attempt=1
while true; do
  log_file="${log_dir}/cockpit-go-test-attempt-${attempt}.log"

  set +e
  go test ./... 2>&1 | tee "$log_file"
  status=${PIPESTATUS[0]}
  set -e

  if [ "$status" -eq 0 ]; then
    exit 0
  fi

  # cockpit-tools v1.3.54+ can race its startup token refresh against this
  # test's auth-file read. Retry only when that known transient truncation
  # signature is present; failures without it remain fatal on the first run.
  if ! grep -Fq -- '--- FAIL: TestAccountConcurrencyGateThroughAuthManager' "$log_file" ||
    ! grep -Fq -- 'parse codex token auth file' "$log_file" ||
    ! grep -Fq -- 'unexpected end of JSON input' "$log_file"; then
    exit "$status"
  fi

  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "::error::Known cockpit-tools auth-file race persisted for ${max_attempts} Go test attempts"
    exit "$status"
  fi

  echo "::warning::Retrying Go tests after known cockpit-tools auth-file truncation race (attempt ${attempt}/${max_attempts})"
  attempt=$((attempt + 1))
done
