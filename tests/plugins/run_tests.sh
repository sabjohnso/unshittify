#!/usr/bin/env bash
# Runs the plugins/ validator's own test suite. The validator is what checks
# the repository's Markdown and JSON; this checks the validator.
set -euo pipefail

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bats "${tests_dir}"/*.bats
