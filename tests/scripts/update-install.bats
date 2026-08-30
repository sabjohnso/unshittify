#!/usr/bin/env bats
# Tests for scripts/update-install.sh, which republishes this repository's
# plugins into the local Claude Code install.
#
# The script's whole reason to exist is that `claude plugin update` is keyed
# on the version string alone: a content change at an unchanged version is
# reported as "already at the latest version" and the stale snapshot stays.
# So the decisions worth testing are which plugins the manifest names, which
# ones an ordinary update would silently skip, and whether the snapshot
# actually matches the tree afterwards. Every one of those is a pure function
# over paths, and none of them runs the `claude` CLI.

load helpers

setup() {
  SCRIPT="${SCRIPTS_DIR}/update-install.sh"
  root="$(fixture_root)"
}

teardown() {
  [ -n "${root:-}" ] && rm -rf "$root"
}

# --- the plugin list comes from the manifest, not from a hardcoded list ----

@test "marketplace_plugin_names lists every plugin the manifest declares" {
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

# --- the no-op case this script exists for -------------------------------

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

# --- did the snapshot actually take? -------------------------------------

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

@test "snapshot_matches_tree ignores a file the install is known not to copy" {
  make_marketplace "$root" fixture alpha
  make_cache "${root}/cache" fixture alpha "0.1.0"
  printf 'notes\n' > "${root}/plugins/alpha/NOTES.org"
  run bash -c 'source "$1"; snapshot_matches_tree "$2" "$2/cache" fixture alpha 0.1.0' \
    _ "$SCRIPT" "$root"
  [ "$status" -eq 0 ]
}

# --- the plan, without running the CLI -----------------------------------

# The commands are asserted line by line, in full. A substring match passes a
# dropped --yes (which makes the real CLI stop and prompt) and passes an
# uninstall and install in the wrong order (which removes the plugin and puts
# the same stale copy back), because both leave the searched-for text present.
@test "dry run prints the marketplace update before any plugin update" {
  make_marketplace "$root" fixture alpha beta
  make_installed "${root}/installed.json" fixture alpha=0.0.1 beta=0.0.1
  run "$SCRIPT" --dry-run --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "claude plugin marketplace update fixture" ]
  [ "${lines[1]}" = "claude plugin update alpha@fixture --yes" ]
  [ "${lines[2]}" = "claude plugin update beta@fixture --yes" ]
}

@test "dry run reinstalls rather than updates a plugin whose version did not move" {
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

@test "--force reinstalls a plugin an ordinary update would have refreshed" {
  make_marketplace "$root" fixture alpha
  make_plugin "$root" alpha "0.9.0"
  make_installed "${root}/installed.json" fixture alpha=0.1.0
  run "$SCRIPT" --dry-run --force --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "claude plugin uninstall alpha@fixture --yes" ]
  [ "${lines[2]}" = "claude plugin install alpha@fixture --yes" ]
}

@test "--help prints usage and succeeds without touching the install" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: update-install.sh"* ]]
  [[ "$output" == *"--verify-only"* ]]
  [[ "$output" != *"claude plugin"* ]]
}

# The stub holds every external binary the script reaches for EXCEPT jq, so
# the run fails on the guard rather than on a missing shell. printf and
# command are builtins and need no entry.
@test "a missing jq is reported rather than producing an empty plugin list" {
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

@test "tree_version fails on a plugin directory that is not there" {
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

@test "verify names a plugin whose manifest has no version rather than skipping it" {
  make_marketplace "$root" fixture alpha
  printf '{"name": "alpha", "description": "d"}\n' \
    > "${root}/plugins/alpha/.claude-plugin/plugin.json"
  run "$SCRIPT" --verify-only --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -ne 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"no version"* ]]
}

@test "a marketplace entry with no plugin directory is reported by verify" {
  make_marketplace "$root" fixture alpha
  rm -rf "${root}/plugins/alpha"
  run "$SCRIPT" --verify-only --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -ne 0 ]
  [[ "$output" == *"alpha"* ]]
}

@test "a single-file component is compared, not only directories" {
  make_marketplace "$root" fixture alpha
  make_cache "${root}/cache" fixture alpha "0.1.0"
  printf '{"a": 1}\n' > "${root}/plugins/alpha/.mcp.json"
  printf '{"a": 2}\n' > "${root}/cache/fixture/alpha/0.1.0/.mcp.json"
  run bash -c 'source "$1"; snapshot_matches_tree "$2" "$2/cache" fixture alpha 0.1.0' \
    _ "$SCRIPT" "$root"
  [ "$status" -ne 0 ]
}

@test "dry run changes nothing on disk" {
  make_marketplace "$root" fixture alpha
  make_installed "${root}/installed.json" fixture alpha=0.0.1
  before="$(find "$root" -type f | sort | xargs md5sum | md5sum)"
  run "$SCRIPT" --dry-run --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -eq 0 ]
  after="$(find "$root" -type f | sort | xargs md5sum | md5sum)"
  [ "$before" = "$after" ]
}

@test "a root with no marketplace manifest is refused" {
  run "$SCRIPT" --dry-run --marketplace fixture --root "$root" \
      --installed "${root}/installed.json" --cache "${root}/cache"
  [ "$status" -ne 0 ]
  [[ "$output" == *"marketplace.json"* ]]
}

@test "an unknown option is refused rather than ignored" {
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

# --- the law snapshot_matches_tree is supposed to obey ---------------------
#
# The script's central claim is that "published" is measured rather than
# assumed: a snapshot matches the tree exactly when the copy is byte-identical
# across every component the harness loads. The four examples above pin that
# for one two-component shape and one canned edit, which is narrower than the
# claim - eight of the ten components are never built, no directory holds more
# than one file, and no component is present on one side and absent on the
# other.
#
# So the law is stated over generated trees instead: reflexivity, that an
# identical copy of an arbitrary shape always matches; and sensitivity, that
# any single change to that copy always breaks the match. A false positive
# here would report a stale install as published, which is the one failure the
# script exists to prevent.
#
# The generator follows the seeded idiom already used in
# tests/hooks/enforce-code-review-internals.bats: a fixed seed advanced only
# through prng_next, so a shape that breaks the law reappears on a rerun.

SNAPSHOT_SEED=20260830
SNAPSHOT_TRIALS=12

# Components the script compares. Kept in the same order as the script's own
# list so a reader can check the two against each other.
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
# components at all and must not affect the verdict.
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

  # Not components. The install does not copy these, so their presence in the
  # tree must never read as a stale snapshot.
  snap_prng_next 3
  for ((i = 0; i < SNAP_VALUE; i++)); do
    printf 'stray\n' > "${dir}/NOTES${i}.org"
  done
}

# component_files_in <dir>
#
# Every file the comparison actually looks at, so a mutation can be aimed at
# one rather than at a stray the script is right to ignore.
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

@test "law: a byte-identical snapshot of any generated tree matches" {
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

@test "law: any single change to the snapshot breaks the match" {
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
    # A shape with no component files at all cannot be mutated; the generator
    # can produce one, and it is the reflexive case, already covered above.
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
# PLUGIN_COMPONENTS names the parts of a plugin the harness loads today. If
# the harness starts loading a new kind, comparing only that list would report
# every plugin as matching while never looking at the new directory - silent
# under-verification, which is worse than a false alarm here because the whole
# point of the check is to catch a copy that did not happen.
#
# So whatever the install actually copied is compared too: an entry present in
# the snapshot is compared against the tree whether or not the list knows the
# name.

@test "an unrecognised directory in the snapshot is still compared" {
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

@test "an unrecognised directory the install did not copy is reported" {
  make_marketplace "$root" fixture alpha
  make_cache "${root}/cache" fixture alpha "0.1.0"
  mkdir -p "${root}/cache/fixture/alpha/0.1.0/output-styles"
  printf 'orphan\n' > "${root}/cache/fixture/alpha/0.1.0/output-styles/s.md"
  run bash -c 'source "$1"; snapshot_matches_tree "$2" "$2/cache" fixture alpha 0.1.0' \
    _ "$SCRIPT" "$root"
  [ "$status" -ne 0 ]
}

@test "a working note beside a plugin is still not a component" {
  make_marketplace "$root" fixture alpha
  make_cache "${root}/cache" fixture alpha "0.1.0"
  printf 'notes\n' > "${root}/plugins/alpha/NOTES.org"
  printf 'readme\n' > "${root}/plugins/alpha/README.md"
  run bash -c 'source "$1"; snapshot_matches_tree "$2" "$2/cache" fixture alpha 0.1.0' \
    _ "$SCRIPT" "$root"
  [ "$status" -eq 0 ]
}
