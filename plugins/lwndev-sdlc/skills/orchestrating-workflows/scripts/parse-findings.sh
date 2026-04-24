#!/usr/bin/env bash
# parse-findings.sh — Parse a reviewing-requirements subagent output dump into
# counts + individual findings (FEAT-028 FR-2).
#
# Usage: parse-findings.sh <subagent-output-file>
#
# Scans the file for:
#   1. The canonical summary line, anchored on the substring
#      `Found **N errors**, **N warnings**, **N info**`.
#      Test-plan mode prepends a prefix; anchor is not line-start, so the
#      prefix is handled transparently. No summary line → zero counts.
#   2. Individual findings matching:
#        **[W1] category — description**
#        **[I3] category — description**
#      Em dash (—) preferred; ASCII double-hyphen (--) accepted. Bold markers
#      (leading/trailing **) optional. Error ([EN]) findings are NOT parsed
#      into individual[] — errors block at the orchestrator layer.
#
# Emits one JSON object on stdout:
#   {"counts":{"errors":0,"warnings":0,"info":0},
#    "individual":[{"id":"W1","severity":"warning","category":"...","description":"..."}]}
#
# Stderr contract:
#   [warn] parse-findings: counts non-zero but no individual findings parsed
#   — recording counts only.
#   Emitted iff counts.warnings + counts.info > 0 AND individual is empty.
#   NOT emitted for error-only counts (errors are intentionally not parsed).
#
# Uses jq for JSON assembly when available; pure-bash printf fallback.
#
# Exit codes:
#   0 success (including zero findings)
#   1 file not found / unreadable
#   2 missing arg

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "[error] parse-findings: usage: parse-findings.sh <subagent-output-file>" >&2
  exit 2
fi

path="$1"

if [ ! -r "$path" ]; then
  echo "[error] parse-findings: file not found: $path" >&2
  exit 1
fi

# --- summary line scan -------------------------------------------------------

errors=0
warnings=0
info=0

# Anchor: Found **<N> error(s)**, **<N> warning(s)**, **<N> info**.
# The canonical shape wraps both number and word together inside the bold
# markers (see `references/reviewing-requirements-flow.md` and
# `reviewing-requirements/references/review-example.md`). Regex uses bash =~
# ERE; tolerant of whitespace / punctuation between the three fields.
summary_re='Found[[:space:]]+\*\*([0-9]+)[[:space:]]+[a-z]+\*\*[^*]*\*\*([0-9]+)[[:space:]]+[a-z]+\*\*[^*]*\*\*([0-9]+)[[:space:]]+[a-z]+\*\*'

while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ $summary_re ]]; then
    errors="${BASH_REMATCH[1]}"
    warnings="${BASH_REMATCH[2]}"
    info="${BASH_REMATCH[3]}"
    break
  fi
done < "$path"

# --- individual findings scan -----------------------------------------------

# Collect individual findings in three parallel arrays.
f_ids=()
f_severities=()
f_categories=()
f_descriptions=()

# Match lines like:
#   **[W1] category — description**
#   [I3] category -- description
# Dash variants: em dash (U+2014), en dash (U+2013), ASCII double-hyphen (--).
# Leading/trailing ** optional.
# The ** markers can also appear after [W1] in some renderings; accept the
# bracket-id-then-optional-space pattern.

# Regex: optional leading **, then [WN] or [IN], optional **, category text
# (no dash chars), dash separator, description. Captures id, category, desc.
# Using a single regex with alternation on the dash character set.
#
# Bash BRE/ERE doesn't support Unicode char classes, so we list em dash and
# en dash bytes explicitly. Em dash UTF-8: E2 80 94; en dash: E2 80 93.
# Use a POSIX character class via double-byte matching—bash =~ handles UTF-8
# when the locale is UTF-8, so literal — / – in the pattern work.

# Strategy: first test for em/en dash; if not found, test for ASCII --.
individual_re_unicode='^\*?\*?\[([WI][0-9]+)\](\*?\*?)[[:space:]]*([^—–]+)[—–]+[[:space:]]*(.+)$'
individual_re_ascii='^\*?\*?\[([WI][0-9]+)\](\*?\*?)[[:space:]]*([^-]+)[[:space:]]--[[:space:]]*(.+)$'

# Trim leading/trailing whitespace (and a trailing ** if present).
_trim() {
  local s="$1"
  # strip leading whitespace
  s="${s#"${s%%[![:space:]]*}"}"
  # strip trailing whitespace
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

_strip_trailing_bold() {
  local s="$1"
  # strip trailing **
  while [[ "$s" == *"**" ]]; do
    s="${s%\*\*}"
  done
  # re-trim after bold strip
  _trim "$s"
}

while IFS= read -r line || [ -n "$line" ]; do
  id=""
  category=""
  description=""

  if [[ "$line" =~ $individual_re_unicode ]]; then
    id="${BASH_REMATCH[1]}"
    category="${BASH_REMATCH[3]}"
    description="${BASH_REMATCH[4]}"
  elif [[ "$line" =~ $individual_re_ascii ]]; then
    id="${BASH_REMATCH[1]}"
    category="${BASH_REMATCH[3]}"
    description="${BASH_REMATCH[4]}"
  else
    continue
  fi

  category="$(_trim "$category")"
  description="$(_strip_trailing_bold "$description")"

  # Skip empty id guard.
  [ -z "$id" ] && continue

  severity=""
  case "${id:0:1}" in
    W) severity="warning" ;;
    I) severity="info" ;;
    *) continue ;;
  esac

  f_ids+=("$id")
  f_severities+=("$severity")
  f_categories+=("$category")
  f_descriptions+=("$description")
done < "$path"

# --- warn emission -----------------------------------------------------------

nonzero_wi=$(( warnings + info ))
if [ "$nonzero_wi" -gt 0 ] && [ "${#f_ids[@]}" -eq 0 ]; then
  echo "[warn] parse-findings: counts non-zero but no individual findings parsed — recording counts only." >&2
fi

# --- JSON emission -----------------------------------------------------------

_have_jq() {
  command -v jq >/dev/null 2>&1
}

_json_escape() {
  # Escape backslashes, double-quotes, and control chars for JSON.
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  # Tabs and newlines (rare in a single line but be safe).
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

emit_json() {
  if _have_jq; then
    # Build individual array as JSON.
    local individual_json="[]"
    local i=0
    while [ "$i" -lt "${#f_ids[@]}" ]; do
      individual_json="$(jq -n \
        --argjson acc "$individual_json" \
        --arg id "${f_ids[$i]}" \
        --arg severity "${f_severities[$i]}" \
        --arg category "${f_categories[$i]}" \
        --arg description "${f_descriptions[$i]}" \
        '$acc + [{id: $id, severity: $severity, category: $category, description: $description}]')"
      i=$((i + 1))
    done

    jq -n \
      --argjson errors "$errors" \
      --argjson warnings "$warnings" \
      --argjson info "$info" \
      --argjson individual "$individual_json" \
      '{
        counts: {errors: $errors, warnings: $warnings, info: $info},
        individual: $individual
      }' -c
    return
  fi

  # pure-bash fallback
  local out="{\"counts\":{\"errors\":$errors,\"warnings\":$warnings,\"info\":$info},\"individual\":["
  local i=0
  local first=1
  while [ "$i" -lt "${#f_ids[@]}" ]; do
    if [ "$first" -eq 0 ]; then
      out+=","
    fi
    local esc_id esc_sev esc_cat esc_desc
    esc_id="$(_json_escape "${f_ids[$i]}")"
    esc_sev="$(_json_escape "${f_severities[$i]}")"
    esc_cat="$(_json_escape "${f_categories[$i]}")"
    esc_desc="$(_json_escape "${f_descriptions[$i]}")"
    out+="{\"id\":\"$esc_id\",\"severity\":\"$esc_sev\",\"category\":\"$esc_cat\",\"description\":\"$esc_desc\"}"
    first=0
    i=$((i + 1))
  done
  out+="]}"
  printf '%s\n' "$out"
}

emit_json
exit 0
