#!/usr/bin/env bash
# Runs every check: shellcheck over the shell code, the runner of each test
# subdirectory, and the validator against this repository. It is the one
# answer to "did I break something". Thus no check depends on a memory to
# run it.
#
# Each suite is delegated to the runner that owns it. This file does not
# repeat it. Thus a new tests/<name>/run_tests.sh is picked up when the file
# is added.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"

# CLAUDE.md makes shellcheck mandatory after an edit to a hook, and nothing
# covered the validator itself. shellcheck runs first. Thus a syntax-level
# defect is named as one. It does not show up as a test failure three suites
# later.
echo "== shellcheck =="
if ! command -v shellcheck >/dev/null 2>&1; then
  printf 'run_tests.sh: shellcheck is necessary and is not on PATH.\n' >&2
  printf 'Install it from https://www.shellcheck.net, or add it to PATH.\n' >&2
  exit 2
fi
# The helpers.bash files of the suites are shell code too. They were not in
# this list while they were edited freely. A check ran only when somebody
# named them by hand, and that is the dependence this runner exists to stop.
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
