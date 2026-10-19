#!/usr/bin/env bats
# Tests for scripts/update-install.sh, which publishes the plugins of this
# repository again into the local Claude Code install.
#
# The script exists because `claude plugin update` keys on the version
# string alone. It reports a content change at an unchanged version as
# "already at the latest version", and the stale snapshot stays. So the
# decisions to test are these: which plugins the manifest names, which ones
# an ordinary update skips with no error, and whether the snapshot matches
# the tree afterwards. Each one is a pure function over paths, and none of
# them runs the `claude` CLI.

load helpers

setup() {
  SCRIPT="${SCRIPTS_DIR}/update-install.sh"
  root="$(fixture_root)"
}

teardown() {
  [ -n "${root:-}" ] && rm -rf "$root"
}

# --- the plugin list comes from the manifest, not from a fixed list -------

@test "marketplace_plugin_names lists every plugin that the manifest declares" {
  make_marketplace "$root" fixture alpha beta gamma
  run bash -c 'source "$1"; marketplace_plugin_names "$2/.claude-plugin/marketplace.json"' \
    _ "$SCRIPT" "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "alpha
beta
gamma" ]
}

@test "marketplace_plugin_names fails on a manifest with no plugins array" {
  mkdir -p "${root}/.claude-plugin"
  printf '{"name": "fixture"}\n' > "${root}/.claude-plugin/marketplace.json"
  run bash -c 'source "$1"; marketplace_plugin_names "$2/.claude-plugin/marketplace.json"' \
    _ "$SCRIPT" "$root"
  [ "$status" -ne 0 ]
}

@test "marketplace_plugin_names fails on a missing manifest" {
  run bash -c 'source "$1"; marketplace_plugin_names "$2/nope.json"' _ "$SCRIPT" "$root"
  [ "$status" -ne 0 ]
}

# --- versions ------------------------------------------------------------

@test "tree_version reads the version from the plugin manifest" {
  make_marketplace "$root" fixture alpha
  make_plugin "$root" alpha "2.5.1"
  run bash -c 'source "$1"; tree_version "$2" alpha' _ "$SCRIPT" "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "2.5.1" ]
}

@test "installed_version reads the version recorded for the marketplace" {
  make_installed "${root}/installed.json" fixture alpha=0.1.0 beta=0.9.0
  run bash -c 'source "$1"; installed_version "$2/installed.json" fixture beta' _ "$SCRIPT" "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "0.9.0" ]
}

@test "installed_version prints nothing for a plugin that is not installed" {
  make_installed "${root}/installed.json" fixture alpha=0.1.0
  run bash -c 'source "$1"; installed_version "$2/installed.json" fixture beta' _ "$SCRIPT" "$root"
  [ -z "$output" ]
}

# --- the no-op case that this script exists for --------------------------

@test "update_would_skip is true when the tree version matches the installed one" {
  make_marketplace "$root" fixture alpha
  make_installed "${root}/installed.json" fixture alpha=0.1.0
  run bash -c 'source "$1"; update_would_skip "$2" "$2/installed.json" fixture alpha' \
    _ "$SCRIPT" "$root"
  [ "$status" -eq 0 ]
}

@test "update_would_skip is false when the tree version is ahead" {
  make_marketplace "$root" fixture alpha
  make_plugin "$root" alpha "0.2.0"
  make_installed "${root}/installed.json" fixture alpha=0.1.0
  run bash -c 'source "$1"; update_would_skip "$2" "$2/installed.json" fixture alpha' \
    _ "$SCRIPT" "$root"
  [ "$status" -ne 0 ]
}

@test "update_would_skip is false for a plugin that is not installed at all" {
  make_marketplace "$root" fixture alpha
  make_installed "${root}/installed.json" fixture
  run bash -c 'source "$1"; update_would_skip "$2" "$2/installed.json" fixture alpha' \
    _ "$SCRIPT" "$root"
  [ "$status" -ne 0 ]
}

# --- did the snapshot occur? ---------------------------------------------

@test "snapshot_matches_tree succeeds when the cached copy equals the tree" {
  make_marketplace "$root" fixture alpha
  make_cache "${root}/cache" fixture alpha "0.1.0"
  run bash -c 'source "$1"; snapshot_matches_tree "$2" "$2/cache" fixture alpha 0.1.0' \
    _ "$SCRIPT" "$root"
  [ "$status" -eq 0 ]
}

@test "snapshot_matches_tree fails when the cached copy has stale content" {
  make_marketplace "$root" fixture alpha
  make_cache "${root}/cache" fixture alpha "0.1.0" "STALE BODY"
  run bash -c 'source "$1"; snapshot_matches_tree "$2" "$2/cache" fixture alpha 0.1.0' \
    _ "$SCRIPT" "$root"
  [ "$status" -ne 0 ]
}

@test "snapshot_matches_tree fails when the cached version directory is absent" {
  make_marketplace "$root" fixture alpha
  mkdir -p "${root}/cache"
  run bash -c 'source "$1"; snapshot_matches_tree "$2" "$2/cache" fixture alpha 0.1.0' \
    _ "$SCRIPT" "$root"
  [ "$status" -ne 0 ]
}

@test "snapshot_matches_tree ignores a file that the install does not copy" {
  make_marketplace "$root" fixture alpha
  make_cache "${root}/cache" fixture alpha "0.1.0"
  printf 'notes\n' > "${root}/plugins/alpha/NOTES.org"
  run bash -c 'source "$1"; snapshot_matches_tree "$2" "$2/cache" fixture alpha 0.1.0' \
    _ "$SCRIPT" "$root"
  [ "$status" -eq 0 ]
}

# --- the plan, with no run of the CLI ------------------------------------

# The tests assert the commands line by line, in full. A substring match
# passes a dropped --yes (which makes the real CLI stop and prompt), and it
# passes an uninstall and an install in the wrong order (which removes the
# plugin and puts the same stale copy back). Both leave the searched text
# present.
@test "a dry run prints the marketplace update before each plugin update" {
  make_marketplace "$root" fixture alpha beta
  make_installed "${root}/installed.json" fixture alpha=0.0.1 beta=0.0.1
  run "$SCRIPT" --dry-run --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "claude plugin marketplace update fixture" ]
  [ "${lines[1]}" = "claude plugin update alpha@fixture --yes" ]
  [ "${lines[2]}" = "claude plugin update beta@fixture --yes" ]
}

@test "a dry run reinstalls a plugin whose version did not move, and does not update it" {
  make_marketplace "$root" fixture alpha
  make_installed "${root}/installed.json" fixture alpha=0.1.0
  run "$SCRIPT" --dry-run --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "claude plugin marketplace update fixture" ]
  [ "${lines[1]}" = "claude plugin uninstall alpha@fixture --yes" ]
  [ "${lines[2]}" = "claude plugin install alpha@fixture --yes" ]
  [[ "$output" != *"plugin update alpha@fixture"* ]]
}

@test "--force reinstalls a plugin that an ordinary update refreshes" {
  make_marketplace "$root" fixture alpha
  make_plugin "$root" alpha "0.9.0"
  make_installed "${root}/installed.json" fixture alpha=0.1.0
  run "$SCRIPT" --dry-run --force --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "claude plugin uninstall alpha@fixture --yes" ]
  [ "${lines[2]}" = "claude plugin install alpha@fixture --yes" ]
}

@test "--help prints the usage, succeeds, and does not touch the install" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: update-install.sh"* ]]
  [[ "$output" == *"--verify-only"* ]]
  [[ "$output" != *"claude plugin"* ]]
}

# The stub holds every external binary that the script uses EXCEPT jq. So
# the run fails on the guard and not on a missing shell. printf and command
# are builtins and need no entry.
@test "the script reports a missing jq and does not produce an empty plugin list" {
  make_marketplace "$root" fixture alpha
  local stub="${root}/stubbin" tool
  mkdir -p "$stub"
  for tool in bash dirname diff find; do
    ln -sf "$(command -v "$tool")" "${stub}/${tool}"
  done
  run env PATH="$stub" bash "$SCRIPT" --dry-run --marketplace fixture --root "$root"
  [ "$status" -eq 2 ]
  [[ "$output" == *"jq is required"* ]]
}

@test "tree_version fails on a plugin directory that does not exist" {
  make_marketplace "$root" fixture alpha
  run bash -c 'source "$1"; tree_version "$2" ghost' _ "$SCRIPT" "$root"
  [ "$status" -ne 0 ]
}

@test "tree_version fails on a plugin manifest with no version field" {
  make_marketplace "$root" fixture alpha
  printf '{"name": "alpha", "description": "d"}\n' \
    > "${root}/plugins/alpha/.claude-plugin/plugin.json"
  run bash -c 'source "$1"; tree_version "$2" alpha' _ "$SCRIPT" "$root"
  [ "$status" -ne 0 ]
}

@test "verify names a plugin whose manifest has no version and does not skip it" {
  make_marketplace "$root" fixture alpha
  printf '{"name": "alpha", "description": "d"}\n' \
    > "${root}/plugins/alpha/.claude-plugin/plugin.json"
  run "$SCRIPT" --verify-only --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -ne 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"no version"* ]]
}

@test "verify reports a marketplace entry with no plugin directory" {
  make_marketplace "$root" fixture alpha
  rm -rf "${root}/plugins/alpha"
  run "$SCRIPT" --verify-only --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -ne 0 ]
  [[ "$output" == *"alpha"* ]]
}

@test "the comparison covers a single-file component, not only directories" {
  make_marketplace "$root" fixture alpha
  make_cache "${root}/cache" fixture alpha "0.1.0"
  printf '{"a": 1}\n' > "${root}/plugins/alpha/.mcp.json"
  printf '{"a": 2}\n' > "${root}/cache/fixture/alpha/0.1.0/.mcp.json"
  run bash -c 'source "$1"; snapshot_matches_tree "$2" "$2/cache" fixture alpha 0.1.0' \
    _ "$SCRIPT" "$root"
  [ "$status" -ne 0 ]
}

@test "a dry run changes nothing on disk" {
  make_marketplace "$root" fixture alpha
  make_installed "${root}/installed.json" fixture alpha=0.0.1
  before="$(find "$root" -type f | sort | xargs md5sum | md5sum)"
  run "$SCRIPT" --dry-run --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -eq 0 ]
  after="$(find "$root" -type f | sort | xargs md5sum | md5sum)"
  [ "$before" = "$after" ]
}

@test "the script refuses a root with no marketplace manifest" {
  run "$SCRIPT" --dry-run --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -ne 0 ]
  [[ "$output" == *"marketplace.json"* ]]
}

@test "the script refuses an unknown option and does not ignore it" {
  make_marketplace "$root" fixture alpha
  run "$SCRIPT" --dry-run --frobnicate --root "$root"
  [ "$status" -ne 0 ]
}

# --- the verification pass -----------------------------------------------

@test "verify reports a plugin whose snapshot is stale and exits nonzero" {
  make_marketplace "$root" fixture alpha beta
  make_cache "${root}/cache" fixture alpha "0.1.0"
  make_cache "${root}/cache" fixture beta "0.1.0" "STALE BODY"
  run "$SCRIPT" --verify-only --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -ne 0 ]
  [[ "$output" == *"beta"* ]]
  [[ "$output" != *"alpha: stale"* ]]
}

@test "verify is silent about mismatches when every snapshot matches" {
  make_marketplace "$root" fixture alpha beta
  make_cache "${root}/cache" fixture alpha "0.1.0"
  make_cache "${root}/cache" fixture beta "0.1.0"
  run "$SCRIPT" --verify-only --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -eq 0 ]
  [[ "$output" != *"stale"* ]]
}

# --- the law that snapshot_matches_tree must obey --------------------------
#
# The central claim of the script is that "published" is measured, not
# assumed. A snapshot matches the tree exactly when the copy is identical
# byte for byte across every component that the harness loads. The four
# examples above pin that for one shape with two components and one fixed
# edit. That is narrower than the claim. Eight of the ten components are
# never built, no directory holds more than one file, and no component is
# present on one side and absent on the other.
#
# So the law is stated over generated trees instead. Reflexivity: an
# identical copy of an arbitrary shape always matches. Sensitivity: a single
# change to that copy always breaks the match. A false positive here reports
# a stale install as published, and that is the one failure that the script
# exists to prevent.
#
# The generator follows the seeded idiom of
# tests/hooks/enforce-code-review-internals.bats: a fixed seed that only
# prng_next advances, so a shape that breaks the law occurs again on a
# rerun.

SNAPSHOT_SEED=20260830
SNAPSHOT_TRIALS=12

# The components that the script compares. They are in the same order as
# the list in the script, so a reader can check the two against each other.
COMPONENT_DIRS=(.claude-plugin skills commands agents hooks monitors bin)
COMPONENT_FILES=(.mcp.json .lsp.json settings.json)

snap_prng_reset() { SNAP_STATE="$SNAPSHOT_SEED"; }

snap_prng_next() {
  SNAP_STATE=$(( (SNAP_STATE * 1103515245 + 12345) % 2147483648 ))
  SNAP_VALUE=$(( (SNAP_STATE / 65536) % $1 ))
}

# generate_tree <dir>
#
# Builds an arbitrary plugin shape: a random subset of the component
# directories, each with a random number of files at a random depth, plus a
# random subset of the single-file components, plus stray paths that are not
# components and must not change the verdict.
generate_tree() {
  local dir="$1" component depth files i path
  mkdir -p "$dir"

  for component in "${COMPONENT_DIRS[@]}"; do
    snap_prng_next 3
    [ "$SNAP_VALUE" -eq 0 ] && continue
    snap_prng_next 2
    depth="$SNAP_VALUE"
    snap_prng_next 3
    files=$(( SNAP_VALUE + 1 ))
    path="${dir}/${component}"
    [ "$depth" -eq 1 ] && path="${path}/nested"
    mkdir -p "$path"
    for ((i = 0; i < files; i++)); do
      snap_prng_next 1000
      printf 'content %s\n' "$SNAP_VALUE" > "${path}/file${i}.md"
    done
  done

  for component in "${COMPONENT_FILES[@]}"; do
    snap_prng_next 2
    [ "$SNAP_VALUE" -eq 0 ] && continue
    snap_prng_next 1000
    printf '{"k": %s}\n' "$SNAP_VALUE" > "${dir}/${component}"
  done

  # Not components. The install does not copy these, so their presence in
  # the tree must never read as a stale snapshot.
  snap_prng_next 3
  for ((i = 0; i < SNAP_VALUE; i++)); do
    printf 'stray\n' > "${dir}/NOTES${i}.org"
  done
}

# component_files_in <dir>
#
# Every file that the comparison reads. Thus a mutation can target one of
# them and not a stray file that the script correctly ignores.
component_files_in() {
  local dir="$1" component
  for component in "${COMPONENT_DIRS[@]}"; do
    [ -d "${dir}/${component}" ] && find "${dir}/${component}" -type f
  done
  for component in "${COMPONENT_FILES[@]}"; do
    [ -f "${dir}/${component}" ] && printf '%s\n' "${dir}/${component}"
  done
  return 0
}

@test "law: a snapshot that is identical byte for byte to a generated tree matches" {
  snap_prng_reset
  local trial
  for ((trial = 0; trial < SNAPSHOT_TRIALS; trial++)); do
    local tree="${root}/t${trial}" snap="${root}/s${trial}"
    mkdir -p "${tree}/plugins/alpha" "${snap}/fixture/alpha"
    generate_tree "${tree}/plugins/alpha"
    cp -a "${tree}/plugins/alpha" "${snap}/fixture/alpha/0.1.0"

    run bash -c 'source "$1"; snapshot_matches_tree "$2" "$3" fixture alpha 0.1.0' \
      _ "$SCRIPT" "$tree" "$snap"
    if [ "$status" -ne 0 ]; then
      echo "identical copy reported stale (seed $SNAPSHOT_SEED, trial $trial)" >&2
      find "${tree}/plugins/alpha" | sed 's/^/  tree: /' >&2
      return 1
    fi
  done
}

@test "law: each single change to the snapshot breaks the match" {
  snap_prng_reset
  local trial
  for ((trial = 0; trial < SNAPSHOT_TRIALS; trial++)); do
    local tree="${root}/mt${trial}" snap="${root}/ms${trial}"
    mkdir -p "${tree}/plugins/alpha" "${snap}/fixture/alpha"
    generate_tree "${tree}/plugins/alpha"
    cp -a "${tree}/plugins/alpha" "${snap}/fixture/alpha/0.1.0"

    local copy="${snap}/fixture/alpha/0.1.0"
    local targets target
    mapfile -t targets < <(component_files_in "$copy")
    # A shape with no component files cannot be mutated. The generator can
    # produce one, and that is the reflexive case, which the test above
    # covers.
    [ "${#targets[@]}" -gt 0 ] || continue

    snap_prng_next "${#targets[@]}"
    target="${targets[$SNAP_VALUE]}"
    snap_prng_next 3
    case "$SNAP_VALUE" in
      0) printf 'mutated\n' >> "$target" ;;
      1) rm -f "$target" ;;
      2) printf 'extra\n' > "$(dirname "$target")/added.md" ;;
    esac

    run bash -c 'source "$1"; snapshot_matches_tree "$2" "$3" fixture alpha 0.1.0' \
      _ "$SCRIPT" "$tree" "$snap"
    if [ "$status" -eq 0 ]; then
      echo "mutation $SNAP_VALUE on $target went undetected (seed $SNAPSHOT_SEED, trial $trial)" >&2
      return 1
    fi
  done
}

# --- a component the script has not heard of ------------------------------
#
# PLUGIN_COMPONENTS names the parts of a plugin that the harness loads
# today. If the harness starts to load a new kind, a comparison of only that
# list reports every plugin as a match and never reads the new directory.
# That is silent under-verification, and it is worse than a false alarm
# here, because the purpose of the check is to catch a copy that did not
# occur.
#
# So the comparison also covers what the install copied. An entry in the
# snapshot is compared against the tree whether the list knows the name or
# not.

@test "the comparison covers an unknown directory in the snapshot" {
  make_marketplace "$root" fixture alpha
  make_cache "${root}/cache" fixture alpha "0.1.0"
  mkdir -p "${root}/plugins/alpha/output-styles" \
           "${root}/cache/fixture/alpha/0.1.0/output-styles"
  printf 'tree\n'  > "${root}/plugins/alpha/output-styles/s.md"
  printf 'stale\n' > "${root}/cache/fixture/alpha/0.1.0/output-styles/s.md"
  run bash -c 'source "$1"; snapshot_matches_tree "$2" "$2/cache" fixture alpha 0.1.0' \
    _ "$SCRIPT" "$root"
  [ "$status" -ne 0 ]
}

@test "the script reports an unknown directory that the install did not copy" {
  make_marketplace "$root" fixture alpha
  make_cache "${root}/cache" fixture alpha "0.1.0"
  mkdir -p "${root}/cache/fixture/alpha/0.1.0/output-styles"
  printf 'orphan\n' > "${root}/cache/fixture/alpha/0.1.0/output-styles/s.md"
  run bash -c 'source "$1"; snapshot_matches_tree "$2" "$2/cache" fixture alpha 0.1.0' \
    _ "$SCRIPT" "$root"
  [ "$status" -ne 0 ]
}

@test "a working note beside a plugin is not a component" {
  make_marketplace "$root" fixture alpha
  make_cache "${root}/cache" fixture alpha "0.1.0"
  printf 'notes\n' > "${root}/plugins/alpha/NOTES.org"
  printf 'readme\n' > "${root}/plugins/alpha/README.md"
  run bash -c 'source "$1"; snapshot_matches_tree "$2" "$2/cache" fixture alpha 0.1.0' \
    _ "$SCRIPT" "$root"
  [ "$status" -eq 0 ]
}
