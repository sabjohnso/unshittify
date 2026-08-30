# Shared helpers for the scripts/ test suite.
#
# Provides SCRIPTS_DIR plus fixture builders. The script under test talks to
# the `claude` CLI and to ~/.claude/plugins, neither of which a test may
# touch, so every fixture here is a throwaway tree and the script is always
# driven with explicit paths.

# shellcheck disable=SC2034 # consumed by the *.bats files that load this.
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)"

# fixture_root
#
# A throwaway directory removed by teardown. Printing the path rather than
# assigning a global keeps a test free to hold more than one.
fixture_root() {
  mktemp -d "${BATS_TEST_TMPDIR:-${BATS_TMPDIR:-/tmp}}/scripts.XXXXXX"
}

# make_marketplace <root> <name> [plugin ...]
#
# Writes a marketplace manifest listing each plugin, and a plugin directory
# with a manifest for each, so a fixture is one call rather than six.
make_marketplace() {
  local root="$1" name="$2"; shift 2
  mkdir -p "${root}/.claude-plugin"
  {
    printf '{\n  "name": "%s",\n  "owner": {"name": "t"},\n' "$name"
    printf '  "description": "fixture",\n  "plugins": [\n'
    local first=1 p
    for p in "$@"; do
      [ "$first" -eq 1 ] || printf ',\n'
      first=0
      printf '    {"name": "%s", "source": "./plugins/%s", "description": "d"}' "$p" "$p"
    done
    printf '\n  ]\n}\n'
  } > "${root}/.claude-plugin/marketplace.json"

  local p
  for p in "$@"; do
    make_plugin "$root" "$p" "0.1.0"
  done
}

# make_plugin <root> <name> <version> [body]
make_plugin() {
  local root="$1" name="$2" version="$3" body="${4:-body}"
  mkdir -p "${root}/plugins/${name}/.claude-plugin" "${root}/plugins/${name}/skills/demo"
  printf '{"name": "%s", "description": "d", "version": "%s"}\n' "$name" "$version" \
    > "${root}/plugins/${name}/.claude-plugin/plugin.json"
  printf -- '---\ndescription: Demo skill. Use when demoing.\n---\n\n# Demo\n\n%s\n' "$body" \
    > "${root}/plugins/${name}/skills/demo/SKILL.md"
}

# make_installed <path> <marketplace> [name=version ...]
#
# The installed_plugins.json shape the script reads: a version per entry,
# keyed "<plugin>@<marketplace>".
make_installed() {
  local path="$1" marketplace="$2"; shift 2
  {
    printf '{\n  "version": 2,\n  "plugins": {\n'
    local first=1 pair name version
    for pair in "$@"; do
      name="${pair%%=*}"; version="${pair#*=}"
      [ "$first" -eq 1 ] || printf ',\n'
      first=0
      printf '    "%s@%s": [{"scope": "user", "version": "%s"}]' "$name" "$marketplace" "$version"
    done
    printf '\n  }\n  }\n'
  } > "$path"
}

# make_cache <cache-root> <marketplace> <plugin> <version> [body]
#
# The snapshot copy an install would have left behind.
make_cache() {
  local cache="$1" marketplace="$2" plugin="$3" version="$4" body="${5:-body}"
  local dir="${cache}/${marketplace}/${plugin}/${version}"
  mkdir -p "${dir}/.claude-plugin" "${dir}/skills/demo"
  printf '{"name": "%s", "description": "d", "version": "%s"}\n' "$plugin" "$version" \
    > "${dir}/.claude-plugin/plugin.json"
  printf -- '---\ndescription: Demo skill. Use when demoing.\n---\n\n# Demo\n\n%s\n' "$body" \
    > "${dir}/skills/demo/SKILL.md"
}
