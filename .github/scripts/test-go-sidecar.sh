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

  # cockpit-tools v1.3.54+ can race its startup token refresh against either
  # auth-file read below. Match the parser error inside that test's FAIL block
  # so unrelated failures cannot combine into a retry signature.
  if ! awk '
    function is_failed_test(name, boundary) {
      if (substr($0, 1, 10) != "--- FAIL: ") return 0
      if (substr($0, 11, length(name)) != name) return 0
      boundary = substr($0, 11 + length(name), 1)
      return boundary == "" || boundary == " " || boundary == "("
    }

    function finish_test() {
      if (test_status == "FAIL") {
        failed_tests++
        if (expected_parser == "" || !signature_seen) invalid = 1
      }
    }

    /^#[[:space:]]/ || /^FAIL[[:space:]].*\[[^]]+\]/ { invalid = 1 }

    /^--- (PASS|FAIL|SKIP): / {
      finish_test()
      test_status = substr($2, 1, length($2) - 1)
      expected_parser = ""
      signature_seen = 0
      if (test_status == "FAIL") {
        if (is_failed_test("TestAccountConcurrencyGateThroughAuthManager")) {
          expected_parser = "codex-or-manifest"
        } else if (is_failed_test("TestAccountConcurrencyGateCoversSessionAffinityHit")) {
          expected_parser = "manifest"
        }
      }
      next
    }

    test_status == "FAIL" && expected_parser == "codex-or-manifest" &&
      (index($0, "parse codex token auth file") ||
       index($0, "parse manifest token auth file")) &&
      index($0, "unexpected end of JSON input") {
      signature_seen = 1
    }

    test_status == "FAIL" && expected_parser == "manifest" &&
      index($0, "parse manifest token auth file") &&
      index($0, "unexpected end of JSON input") {
      signature_seen = 1
    }

    END {
      finish_test()
      exit (invalid || failed_tests == 0)
    }
  ' "$log_file"; then
    exit "$status"
  fi

  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "::error::Known cockpit-tools auth-file races persisted for ${max_attempts} Go test attempts"
    exit "$status"
  fi

  echo "::warning::Retrying Go tests after known cockpit-tools auth-file truncation race (attempt ${attempt}/${max_attempts})"
  attempt=$((attempt + 1))
done
