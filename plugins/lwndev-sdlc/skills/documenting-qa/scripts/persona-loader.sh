# persona-loader.sh — sourced helper that loads a persona prompt overlay
#
# Usage (from another shell script):
#   # shellcheck source=./persona-loader.sh
#   source "$(dirname "$0")/persona-loader.sh"
#   load_persona qa "$(dirname "$0")/.."
#
# Exposes a single function `load_persona <name> <skill_dir>` that:
#   1. Resolves `${skill_dir}/personas/${name}.md`.
#   2. Verifies the file exists; on missing, writes a clear error to stderr
#      listing available personas and returns non-zero.
#   3. Parses the YAML frontmatter (opening `---`, closing `---`) and
#      validates that a non-empty `name:` field is present. On malformed
#      frontmatter, writes a clear error to stderr and returns non-zero.
#   4. On success, prints the full persona file contents (frontmatter +
#      body) to stdout so it can be concatenated into a prompt.
#
# This file is intended to be *sourced*, not executed. There is no
# shebang, and the file takes no top-level action.
#
# Error format (stderr): `persona-loader: error: <message>`
# Exit/return codes:
#   0 — success, persona content emitted to stdout
#   non-zero — missing file, unreadable file, or malformed frontmatter

# Enable strict mode when sourced so errors propagate to the caller.
set -euo pipefail

# load_persona <persona_name> <skill_dir>
#
# Arguments:
#   $1 — persona name (e.g. "qa"); resolves to ${skill_dir}/personas/${1}.md
#   $2 — skill directory containing the `personas/` subdirectory
#
# Returns 0 on success; non-zero on any error. On error, writes
# `persona-loader: error: <message>` to stderr.
load_persona() {
  local persona_name="${1:-}"
  local skill_dir="${2:-}"

  if [[ -z "$persona_name" ]]; then
    echo "persona-loader: error: persona name is required (usage: load_persona <name> <skill_dir>)" >&2
    return 2
  fi
  if [[ -z "$skill_dir" ]]; then
    echo "persona-loader: error: skill directory is required (usage: load_persona <name> <skill_dir>)" >&2
    return 2
  fi

  local personas_dir="${skill_dir}/personas"
  local persona_file="${personas_dir}/${persona_name}.md"

  if [[ ! -f "$persona_file" ]]; then
    local available=""
    if [[ -d "$personas_dir" ]]; then
      available="$(ls "$personas_dir" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
    fi
    if [[ -z "$available" ]]; then
      available="(none found)"
    fi
    echo "persona-loader: error: persona file not found at ${persona_file}. Available personas: ${available}" >&2
    return 1
  fi

  if [[ ! -r "$persona_file" ]]; then
    echo "persona-loader: error: persona file at ${persona_file} is not readable" >&2
    return 1
  fi

  # Validate frontmatter: opening `---` on line 1, closing `---` within the
  # first 100 lines, and a non-empty `name:` field within the block.
  local first_line
  first_line="$(head -n 1 "$persona_file")"
  if [[ "$first_line" != "---" ]]; then
    echo "persona-loader: error: persona file at ${persona_file} has missing or malformed frontmatter (expected opening --- on line 1)" >&2
    return 1
  fi

  # Extract frontmatter block (lines between the first two `---` lines).
  local frontmatter
  frontmatter="$(awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---"   { exit }
    in_fm                  { print }
  ' "$persona_file")"

  # Check that the awk actually saw a closing `---` by counting the --- lines.
  local delim_count
  delim_count="$(grep -c '^---$' "$persona_file" || true)"
  if [[ "$delim_count" -lt 2 ]]; then
    echo "persona-loader: error: persona file at ${persona_file} has missing or malformed frontmatter (expected closing --- delimiter)" >&2
    return 1
  fi

  # Validate the `name:` field is present and non-empty. Strip YAML comments
  # (anything after `#`) and whitespace before checking. `|| true` guards
  # against grep returning 1 (no match) killing the function under `set -e`.
  local name_value
  name_value="$(echo "$frontmatter" \
    | grep -E '^[[:space:]]*name[[:space:]]*:' \
    | head -n 1 \
    | sed -E 's/^[[:space:]]*name[[:space:]]*:[[:space:]]*//' \
    | sed -E 's/[[:space:]]*#.*$//' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | sed -E 's/^["'"'"']//; s/["'"'"']$//' \
    || true)"

  if [[ -z "$name_value" ]]; then
    echo "persona-loader: error: persona file at ${persona_file} has missing or malformed frontmatter (expected: name: field)" >&2
    return 1
  fi

  # Success: emit the full file contents (frontmatter + body) to stdout.
  cat "$persona_file"
  return 0
}
