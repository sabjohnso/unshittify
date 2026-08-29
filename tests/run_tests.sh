#!/usr/bin/env bash
# Runs everything: the hook test suites, the validator's own test suite, and
# the validator against this repository. One obvious answer to "did I break
# anything", so that nothing is verified only by remembering to verify it.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"

echo "== hooks =="
bats "${here}"/hooks/*.bats

echo
echo "== plugins validator (self-test) =="
bats "${here}"/plugins/*.bats

echo
echo "== plugins validator (this repository) =="
"${here}/plugins/validate-plugins.sh" "$root"
