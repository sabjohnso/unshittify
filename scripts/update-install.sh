#!/usr/bin/env bash
# Republishes this repository's plugins into the local Claude Code install.
#
# Editing a file under plugins/ changes nothing a session sees. Installing
# copies the tree into ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/,
# and that copy - never the working tree - is what a session loads. So an edit
# reaches a session only after the marketplace is refreshed and the plugin is
# reinstalled.
#
# The reason this is a script rather than a documented pair of commands is the
# no-op. `claude plugin update` is keyed on the version STRING: when the tree's
# version equals the installed one it reports "already at the latest version"
# and leaves the stale snapshot in place, whatever the content says. A plugin
# edited without a version bump is therefore silently not published, and the
# report says success. This script detects that case ahead of time and
# reinstalls those plugins instead, then verifies every snapshot against the
# tree so "published" is a measured claim rather than an assumed one.
#
# Nothing here writes to the repository. The only state it changes is the
# local install, and only when neither --dry-run nor --verify-only is given.
set -euo pipefail

DEFAULT_MARKETPLACE="unshittify"

# The parts of a plugin directory the harness loads, per the documented plugin
# structure. Comparing these rather than the whole directory keeps an untracked
# working note or an editor backup beside a plugin from reading as a stale
# snapshot - the copy legitimately does not contain them.
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
# The plugin names the manifest declares, one per line, in manifest order.
# Reading them here rather than hardcoding a list means adding a plugin to the
# marketplace is the only edit needed to have it published.
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
# Empty output means "not installed", which is not an error: a plugin added to
# the marketplace since the last install has no entry yet and needs installing
# rather than updating.
installed_version() {
  local installed="$1" marketplace="$2" plugin="$3"
  [ -f "$installed" ] || return 0
  jq -r --arg key "${plugin}@${marketplace}" \
    '.plugins[$key][0].version // empty' "$installed" 2>/dev/null || true
}

# --- the decision this script exists to make -------------------------------

# update_would_skip <root> <installed.json> <marketplace> <plugin>
#
# Succeeds when `claude plugin update` would report the plugin already current
# and copy nothing, because the tree's version equals the installed one. Those
# are the plugins an update silently fails to publish.
update_would_skip() {
  local root="$1" installed="$2" marketplace="$3" plugin="$4"
  local tree have
  tree=$(tree_version "$root" "$plugin") || return 1
  have=$(installed_version "$installed" "$marketplace" "$plugin")
  [ -n "$have" ] && [ "$have" = "$tree" ]
}

# snapshot_matches_tree <root> <cache-root> <marketplace> <plugin> <version>
#
# Succeeds when the installed snapshot is byte-identical to the tree. This is
# the check that makes "published" verifiable: the update command's own success
# message cannot distinguish a copy that happened from one that was skipped.
#
# Neither side alone is authoritative, so the names compared are the union of
# both. Everything the install actually COPIED is compared, whatever its name -
# a component kind the harness starts loading after PLUGIN_COMPONENTS was
# written would otherwise go uncompared, and silently reporting a match is
# worse here than a false alarm. Every component named in PLUGIN_COMPONENTS is
# compared too, which catches the reverse: one the install failed to copy at
# all.
snapshot_matches_tree() {
  local root="$1" cache="$2" marketplace="$3" plugin="$4" version="$5"
  local snapshot="${cache}/${marketplace}/${plugin}/${version}"
  local source="${root}/plugins/${plugin}"
  [ -d "$snapshot" ] || return 1

  # The names are collected before any comparison so a component present on
  # both sides is diffed once rather than once per reason for looking at it.
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
# The single place the CLI is invoked, so --dry-run is one branch rather than
# one per call site, and a test can drive every decision above without the
# `claude` binary being present at all. The flag is a parameter rather than a
# global so this function's behaviour is readable from its own signature.
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
    # An unchanged version makes `update` a no-op, so the only way to replace
    # the snapshot is to remove it and install again.
    run_claude "$dry_run" plugin uninstall "${plugin}@${marketplace}" --yes
    run_claude "$dry_run" plugin install "${plugin}@${marketplace}" --yes
  else
    run_claude "$dry_run" plugin update "${plugin}@${marketplace}" --yes
  fi
}

# verify <root> <cache> <marketplace> <plugin...>
#
# Prints one line per plugin whose snapshot does not match the tree, and fails
# if there were any. Silence is the success report.
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
      printf '  %s: stale - the installed copy at %s does not match the tree\n' \
        "$plugin" "${cache}/${marketplace}/${plugin}/${version}"
      stale=1
    fi
  done
  [ "$stale" -eq 0 ]
}

usage() {
  cat <<'USAGE'
Usage: update-install.sh [options]

Refreshes the local Claude Code install from this repository's working tree,
then verifies that every installed snapshot matches it.

  --marketplace NAME   marketplace to refresh (default: unshittify)
  --root DIR           repository root (default: this script's repository)
  --installed FILE     installed_plugins.json to read
  --cache DIR          plugin cache root to verify against
  --force              reinstall every plugin, not only the ones an update skips
  --dry-run            print the commands without running them
  --verify-only        skip the update entirely and only report stale snapshots
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
    printf 'update-install: jq is required and is not on PATH.\n' >&2
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

  # A dry run copied nothing, so every snapshot would report stale and the
  # report would be noise rather than news.
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
