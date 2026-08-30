#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v bats >/dev/null 2>&1; then
  printf 'run_tests.sh: bats is required and is not on PATH.\n' >&2
  printf 'Install bats-core from https://github.com/bats-core/bats-core.\n' >&2
  exit 2
fi
exec bats "${here}"/*.bats
