#!/usr/bin/env bash
# Runs everything: shellcheck over the shell code, each test subdirectory's
# own runner, and the validator against this repository. One obvious answer
# to "did I break anything", so that nothing is verified only by remembering
# to verify it.
#
# Each suite is delegated to the runner that owns it rather than re-spelled
# here, so a new tests/<name>/run_tests.sh is picked up by adding the file.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"

# CLAUDE.md makes shellcheck mandatory after editing any hook, and the
# validator itself was covered by nothing at all. Running it first means a
# syntax-level defect is named as one rather than surfacing as a test
# failure three suites later.
echo "== shellcheck =="
if ! command -v shellcheck >/dev/null 2>&1; then
  printf 'run_tests.sh: shellcheck is required and is not on PATH.\n' >&2
  printf 'Install it from https://www.shellcheck.net, or add it to PATH.\n' >&2
  exit 2
fi
# The suites' helpers.bash files are shell code too, and were left out of
# this list while being edited freely - checked only when someone remembered
# to name them by hand, which is the very thing this runner exists to stop.
shellcheck "${root}"/hooks/*.sh "${root}"/hooks/lib/*.sh \
           "${root}"/scripts/*.sh \
           "${root}"/tests/plugins/validate-plugins.sh \
           "${root}"/tests/run_tests.sh \
           "${root}"/tests/*/run_tests.sh \
           "${root}"/tests/*/helpers.bash
echo "shellcheck: clean."

for runner in "${here}"/*/run_tests.sh; do
  [ -x "$runner" ] || continue
  suite="$(dirname "$runner")"
  echo
  echo "== ${suite##*/} =="
  "$runner"
done

echo
echo "== plugins validator (this repository) =="
"${here}/plugins/validate-plugins.sh" "$root"
