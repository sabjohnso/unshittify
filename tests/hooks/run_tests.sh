#!/usr/bin/env bash
# Runs the full bats test suite of hooks/ and reports pass or fail, with a
# nonzero exit on a failure. It is a wrapper around `bats`. Thus "how do I
# run the hook tests" always has one answer.
set -euo pipefail

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v bats >/dev/null 2>&1; then
  printf 'run_tests.sh: bats (bats-core) is necessary and is not on PATH.\n' >&2
  printf 'Install it from https://github.com/bats-core/bats-core, or add it to PATH.\n' >&2
  exit 2
fi

exec bats "${tests_dir}"/*.bats
