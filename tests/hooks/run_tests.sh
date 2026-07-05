#!/usr/bin/env bash
# Runs the full hooks/ bats test suite and reports pass/fail with a
# nonzero exit on any failure. Convenience wrapper around `bats` so
# "how do I run the hook tests" always has one obvious answer.
set -euo pipefail

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bats "${tests_dir}"/*.bats
