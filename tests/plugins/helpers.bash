# Shared helpers for the test suite of the plugins/ validator.
#
# Every test builds a THROWAWAY marketplace tree. It does not assert against
# the real plugins/ directory. A test that asserts against live repository
# content fails each time the content changes for a good reason, and that
# teaches people to edit the test and not the code. A fixture tree pins the
# rule itself.

# shellcheck disable=SC2034 # The .bats files that load this file use it.
VALIDATOR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/validate-plugins.sh"

# fixture_dir. The directory that holds every fixture tree.
#
# It is named here. Each helper does not append to an array, because
# new_marketplace runs in a command substitution. An array that it appended
# to would go with the subshell, and teardown would have nothing to delete.
fixture_dir() {
  printf '%s' "${BATS_TEST_TMPDIR:-${BATS_TMPDIR:-/tmp}}"
}

# cleanup_fixtures. Removes every tree that these helpers created.
cleanup_fixtures() {
  local dir
  dir="$(fixture_dir)"
  rm -rf "${dir}"/marketplace.* "${dir}"/fixture.*
}

# new_marketplace
#
# Creates an empty marketplace root with a valid top-level manifest and
# prints its path. A caller adds plugins to it with add_plugin.
new_marketplace() {
  local root
  root="$(mktemp -d "$(fixture_dir)/marketplace.XXXXXX")"
  mkdir -p "${root}/.claude-plugin"
  jq -n '{name:"fixture", owner:{name:"Fixture Owner"}, plugins:[]}' \
    > "${root}/.claude-plugin/marketplace.json"
  printf '%s' "$root"
}

# add_plugin <root> <name> [description]
#
# Adds a plugin directory with its own manifest AND the matching entry in
# the marketplace manifest. Thus a tree built this way starts consistent,
# and a test only has to add the one defect that it pins.
add_plugin() {
  local root="$1" name="$2" description="${3:-A fixture plugin.}"
  mkdir -p "${root}/plugins/${name}/.claude-plugin"
  jq -n --arg n "$name" --arg d "$description" \
    '{name:$n, description:$d, version:"0.1.0", author:{name:"Fixture Owner"}}' \
    > "${root}/plugins/${name}/.claude-plugin/plugin.json"
  local manifest="${root}/.claude-plugin/marketplace.json"
  jq --arg n "$name" --arg d "$description" \
    '.plugins += [{name:$n, source:("./plugins/" + $n), description:$d}]' \
    "$manifest" > "${manifest}.tmp" && mv "${manifest}.tmp" "$manifest"
}

# add_skill <root> <plugin> <skill> <frontmatter-body> [markdown-body]
add_skill() {
  local root="$1" plugin="$2" skill="$3" frontmatter="$4" body="${5:-Goal: do the fixture thing.}"
  mkdir -p "${root}/plugins/${plugin}/skills/${skill}"
  printf -- '---\n%s\n---\n\n# %s\n\n%s\n' "$frontmatter" "$skill" "$body" \
    > "${root}/plugins/${plugin}/skills/${skill}/SKILL.md"
}

# add_agent <root> <plugin> <agent> <frontmatter-body>
add_agent() {
  local root="$1" plugin="$2" agent="$3" frontmatter="$4"
  mkdir -p "${root}/plugins/${plugin}/agents"
  printf -- '---\n%s\n---\n\n# %s\n\nYou do the fixture thing.\n' "$frontmatter" "$agent" \
    > "${root}/plugins/${plugin}/agents/${agent}.md"
}

# add_sibling <root> <plugin> <skill> <filename> [content]
add_sibling() {
  local root="$1" plugin="$2" skill="$3" filename="$4" content="${5:-A large lookup table.}"
  printf '%s\n' "$content" > "${root}/plugins/${plugin}/skills/${skill}/${filename}"
}

# write_raw_skill <root> <plugin> <skill> <whole-file-content>
#
# For a fixture whose defect is in the frame of the file: a missing closing
# delimiter, CRLF line ends, or a byte-order mark. The printf template of
# add_skill cannot express those.
write_raw_skill() {
  local root="$1" plugin="$2" skill="$3" content="$4"
  mkdir -p "${root}/plugins/${plugin}/skills/${skill}"
  printf '%s' "$content" > "${root}/plugins/${plugin}/skills/${skill}/SKILL.md"
}

# write_raw_agent <root> <plugin> <agent> <whole-file-content>
write_raw_agent() {
  local root="$1" plugin="$2" agent="$3" content="$4"
  mkdir -p "${root}/plugins/${plugin}/agents"
  printf '%s' "$content" > "${root}/plugins/${plugin}/agents/${agent}.md"
}

# A well-formed skill frontmatter, for a tree where the skill is not the
# subject of the test.
valid_skill_frontmatter() {
  printf 'description: Does the fixture thing. Use when the user asks for a fixture.'
}

valid_agent_frontmatter() {
  local name="$1"
  printf 'name: %s\ndescription: Does the fixture thing. Use when delegating a fixture.\ntools: Read, Grep\nmodel: haiku' "$name"
}
