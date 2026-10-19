#!/usr/bin/env bash
# Publishes the plugins of this repository again into the local Claude Code
# install.
#
# An edit of a file under plugins/ changes nothing that a session sees. An
# install copies the tree into
# ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/, and a session
# loads that copy, never the working tree. So an edit reaches a session only
# after a refresh of the marketplace and a new install of the plugin.
#
# This is a script and not a documented pair of commands because of the
# no-op. `claude plugin update` keys on the version STRING. When the version
# in the tree equals the installed one, it reports "already at the latest
# version" and leaves the stale snapshot in place, whatever the content
# says. So a plugin edited with no version increase is not published, and
# the report says success. This script finds that case before it occurs and
# reinstalls those plugins instead. Then it verifies every snapshot against
# the tree, so "published" is a measured claim and not an assumed one.
#
# Nothing here writes to the repository. The only state that the script
# changes is the local install, and only when neither --dry-run nor
# --verify-only is given.
set -euo pipefail

DEFAULT_MARKETPLACE="unshittify"

# The parts of a plugin directory that the harness loads, per the documented
# plugin structure. The comparison covers these and not the whole directory.
# Thus an untracked working note or an editor backup beside a plugin does not
# read as a stale snapshot. The copy correctly does not hold them.
PLUGIN_COMPONENTS=(
  .claude-plugin
  skills
  commands
  agents
  hooks
  monitors
  bin
  .mcp.json
  .lsp.json
  settings.json
)

# --- reading the manifests -------------------------------------------------

# marketplace_plugin_names <marketplace.json>
#
# The plugin names that the manifest declares, one per line, in manifest
# order. The function reads them and does not hold a fixed list. Thus the
# only edit necessary to publish a new plugin is its entry in the
# marketplace.
marketplace_plugin_names() {
  local manifest="$1"
  [ -f "$manifest" ] || {
    printf 'update-install: no marketplace.json at %s\n' "$manifest" >&2
    return 1
  }
  local names
  if ! names=$(jq -er '.plugins[]?.name' "$manifest" 2>/dev/null); then
    printf 'update-install: %s declares no plugins array\n' "$manifest" >&2
    return 1
  fi
  [ -n "$names" ] || {
    printf 'update-install: %s declares no plugins\n' "$manifest" >&2
    return 1
  }
  printf '%s\n' "$names"
}

# tree_version <root> <plugin>
tree_version() {
  local manifest="$1/plugins/$2/.claude-plugin/plugin.json"
  [ -f "$manifest" ] || return 1
  jq -er '.version // empty' "$manifest" 2>/dev/null
}

# installed_version <installed_plugins.json> <marketplace> <plugin>
#
# Empty output means "not installed", and that is not an error. A plugin
# added to the marketplace after the last install has no entry yet. It needs
# an install, not an update.
installed_version() {
  local installed="$1" marketplace="$2" plugin="$3"
  [ -f "$installed" ] || return 0
  jq -r --arg key "${plugin}@${marketplace}" \
    '.plugins[$key][0].version // empty' "$installed" 2>/dev/null || true
}

# --- the decision this script exists to make -------------------------------

# update_would_skip <root> <installed.json> <marketplace> <plugin>
#
# Succeeds when `claude plugin update` reports the plugin as current and
# copies nothing, because the version in the tree equals the installed one.
# Those are the plugins that an update fails to publish with no error.
update_would_skip() {
  local root="$1" installed="$2" marketplace="$3" plugin="$4"
  local tree have
  tree=$(tree_version "$root" "$plugin") || return 1
  have=$(installed_version "$installed" "$marketplace" "$plugin")
  [ -n "$have" ] && [ "$have" = "$tree" ]
}

# snapshot_matches_tree <root> <cache-root> <marketplace> <plugin> <version>
#
# Succeeds when the installed snapshot is identical to the tree byte for
# byte. This check makes "published" verifiable. The success message of the
# update command cannot tell a copy that occurred from one that was skipped.
#
# Neither side alone is authoritative, so the names in the comparison are
# the union of both. The comparison covers all that the install COPIED,
# whatever its name. Otherwise a component kind that the harness starts to
# load after PLUGIN_COMPONENTS was written is never compared, and a false
# match with no error is worse here than a false alarm. The comparison also
# covers every component in PLUGIN_COMPONENTS. That catches the reverse
# case, a component that the install did not copy at all.
snapshot_matches_tree() {
  local root="$1" cache="$2" marketplace="$3" plugin="$4" version="$5"
  local snapshot="${cache}/${marketplace}/${plugin}/${version}"
  local source="${root}/plugins/${plugin}"
  [ -d "$snapshot" ] || return 1

  # The function collects the names before the first comparison. Thus a
  # component present on both sides gets one diff, not one diff per reason
  # to read it.
  local -A names=()
  local component entry name
  for component in "${PLUGIN_COMPONENTS[@]}"; do names["$component"]=1; done
  for entry in "$snapshot"/* "$snapshot"/.[!.]*; do
    [ -e "$entry" ] || continue
    names["${entry##*/}"]=1
  done

  for name in "${!names[@]}"; do
    [ -e "${source}/${name}" ] || [ -e "${snapshot}/${name}" ] || continue
    diff -r "${source}/${name}" "${snapshot}/${name}" >/dev/null 2>&1 || return 1
  done
}

# --- running the CLI -------------------------------------------------------

# run_claude <dry-run> <args...>
#
# The single place that runs the CLI. Thus --dry-run is one branch and not
# one branch per call site, and a test can drive every decision above with
# no `claude` binary present. The flag is a parameter and not a global, so
# the signature of this function shows its behavior.
run_claude() {
  local dry_run="$1"; shift
  if [ "$dry_run" -eq 1 ]; then
    printf 'claude %s\n' "$*"
    return 0
  fi
  claude "$@"
}

# --- the passes ------------------------------------------------------------

# publish_plugin <dry-run> <force> <root> <installed> <marketplace> <plugin>
publish_plugin() {
  local dry_run="$1" force="$2" root="$3" installed="$4" marketplace="$5" plugin="$6"
  if [ "$force" -eq 1 ] || update_would_skip "$root" "$installed" "$marketplace" "$plugin"; then
    # An unchanged version makes `update` a no-op. So the only way to
    # replace the snapshot is to remove it and install again.
    run_claude "$dry_run" plugin uninstall "${plugin}@${marketplace}" --yes
    run_claude "$dry_run" plugin install "${plugin}@${marketplace}" --yes
  else
    run_claude "$dry_run" plugin update "${plugin}@${marketplace}" --yes
  fi
}

# verify <root> <cache> <marketplace> <plugin...>
#
# Prints one line per plugin whose snapshot does not match the tree, and
# fails if there was one. Silence is the success report.
verify() {
  local root="$1" cache="$2" marketplace="$3"; shift 3
  local plugin version stale=0
  for plugin in "$@"; do
    version=$(tree_version "$root" "$plugin") || {
      printf '  %s: no version in plugins/%s/.claude-plugin/plugin.json\n' "$plugin" "$plugin"
      stale=1
      continue
    }
    if ! snapshot_matches_tree "$root" "$cache" "$marketplace" "$plugin" "$version"; then
      printf '  %s: stale. The installed copy at %s does not match the tree.\n' \
        "$plugin" "${cache}/${marketplace}/${plugin}/${version}"
      stale=1
    fi
  done
  [ "$stale" -eq 0 ]
}

usage() {
  cat <<'USAGE'
Usage: update-install.sh [options]

Refreshes the local Claude Code install from the working tree of this
repository, then verifies that every installed snapshot matches it.

  --marketplace NAME   marketplace to refresh (default: unshittify)
  --root DIR           repository root (default: this script's repository)
  --installed FILE     installed_plugins.json to read
  --cache DIR          plugin cache root to verify against
  --force              reinstall every plugin, not only the ones that an update skips
  --dry-run            print the commands and do not run them
  --verify-only        skip the update and only report the stale snapshots
  -h, --help           this message

Restart Claude Code, or run /reload-plugins, before the new copies take effect.
USAGE
}

main() {
  local here root marketplace installed cache
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  root="$(dirname "$here")"
  marketplace="$DEFAULT_MARKETPLACE"
  installed="${HOME}/.claude/plugins/installed_plugins.json"
  cache="${HOME}/.claude/plugins/cache"
  local dry_run=0 force=0 verify_only=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --marketplace) marketplace="$2"; shift 2 ;;
      --root)        root="$2";        shift 2 ;;
      --installed)   installed="$2";   shift 2 ;;
      --cache)       cache="$2";       shift 2 ;;
      --force)       force=1;          shift ;;
      --dry-run)     dry_run=1;        shift ;;
      --verify-only) verify_only=1;    shift ;;
      -h|--help)     usage; return 0 ;;
      *)
        printf 'update-install: unknown option %s\n\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  command -v jq >/dev/null 2>&1 || {
    printf 'update-install: jq is required and is not on PATH. Install it.\n' >&2
    return 2
  }

  local names
  names=$(marketplace_plugin_names "${root}/.claude-plugin/marketplace.json") || return 1
  local plugins=()
  mapfile -t plugins <<< "$names"

  if [ "$verify_only" -eq 0 ]; then
    run_claude "$dry_run" plugin marketplace update "$marketplace"
    local plugin
    for plugin in "${plugins[@]}"; do
      publish_plugin "$dry_run" "$force" "$root" "$installed" "$marketplace" "$plugin"
    done
  fi

  # A dry run copied nothing. So every snapshot reports stale, and the
  # report is noise and not news.
  if [ "$dry_run" -eq 1 ]; then
    printf '\nDry run: nothing was changed.\n'
    return 0
  fi

  printf '\nVerifying installed snapshots against the tree:\n'
  if verify "$root" "$cache" "$marketplace" "${plugins[@]}"; then
    printf '  all %d plugins match.\n' "${#plugins[@]}"
    [ "$verify_only" -eq 1 ] || printf '\nRestart Claude Code, or run /reload-plugins, to load them.\n'
    return 0
  fi
  printf '\nRe-run with --force to reinstall the plugins listed above.\n' >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
