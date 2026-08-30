#!/usr/bin/env bash
# Runs the full hooks/ bats test suite and reports pass/fail with a
# nonzero exit on any failure. Convenience wrapper around `bats` so
# "how do I run the hook tests" always has one obvious answer.
set -euo pipefail

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v bats >/dev/null 2>&1; then
  printf 'run_tests.sh: bats (bats-core) is required and is not on PATH.\n' >&2
  printf 'Install it from https://github.com/bats-core/bats-core, or add it to PATH.\n' >&2
  exit 2
fi

exec bats "${tests_dir}"/*.bats
