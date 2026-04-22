#!/usr/bin/env bash
# render-issue-comment.sh — Render an issue-comment body from a template + context.
#
# Usage: render-issue-comment.sh <backend> <type> <context-json> [<tier>]
#
# Arguments:
#   <backend>      github | jira
#   <type>         phase-start | phase-completion | work-start | work-complete
#                  | bug-start | bug-complete
#   <context-json> JSON object of template variables
#   <tier>         (optional) rovo | acli   (default: acli)
#
# Template source:
#   github backend, OR jira backend + acli tier → markdown template from
#     ${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/references/github-templates.md
#   jira backend + rovo tier                    → ADF JSON template from
#     ${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/references/jira-templates.md
#
# The template directory can be overridden via the MWI_TEMPLATES_DIR env var
# (used by the bats fixture). When unset, falls back to the sibling
# `../references/` directory relative to this script.
#
# Substitution semantics:
#
# Markdown templates (<PLACEHOLDER> style):
#   * Scalar placeholders: `<FOO>` / `<FOO_BAR>` replaced with the matching
#     context value. Context keys are normalized (camelCase and snake_case
#     accepted): `phase` matches `<PHASE>`; `workItemId` matches
#     `<WORK_ITEM_ID>`.
#   * List placeholders: the canonical list tokens <DELIVERABLES>, <STEPS>,
#     <CRITERIA>, <ROOT_CAUSES>, <VERIFICATION_RESULTS>,
#     <ROOT_CAUSE_RESOLUTIONS> are expanded into one `- <item>` bullet line
#     per entry in the corresponding JSON array.
#   * Unknown context key (not referenced by any placeholder): emit
#     `[warn] render-issue-comment: unused context variable: <key>` on stderr
#     and continue.
#   * Missing variable (placeholder present, context key absent): leave the
#     placeholder; after full substitution, any remaining `<[A-Z_]+>` token
#     causes exit 1 with an unresolved-placeholder error. No partial output
#     is emitted in this case.
#
# ADF JSON templates ({placeholder} style):
#   * Scalar placeholders: `{foo}` / `{fooBar}` replaced directly in text
#     fields.
#   * List placeholders: bulletList/orderedList nodes in the template show
#     two `listItem` entries as a structural example with `{key[0]}` and
#     `{key[1]}` placeholders; at render time we regenerate one `listItem`
#     per array entry.
#   * Object-list placeholders: `{key[N].field}` is accessed per entry.
#   * After substitution the output is validated as JSON. Malformed result
#     → exit 1.
#
# Exit codes:
#   0 success; rendered body written to stdout
#   1 render failure (template missing, malformed ADF after substitution,
#     unsubstituted placeholder remaining in output)
#   2 invalid args (bad backend, bad type, malformed JSON)

set -euo pipefail

# ---------- arg validation ----------

if [ "$#" -lt 3 ]; then
  echo "[error] usage: render-issue-comment.sh <backend> <type> <context-json> [<tier>]" >&2
  exit 2
fi

backend="$1"
type_="$2"
context_json="$3"
tier="${4:-acli}"

case "$backend" in
  github|jira) ;;
  *)
    echo "[error] render-issue-comment: invalid backend: ${backend}" >&2
    exit 2
    ;;
esac

case "$type_" in
  phase-start|phase-completion|work-start|work-complete|bug-start|bug-complete) ;;
  *)
    echo "[error] render-issue-comment: invalid type: ${type_}" >&2
    exit 2
    ;;
esac

case "$tier" in
  rovo|acli) ;;
  *)
    echo "[error] render-issue-comment: invalid tier: ${tier}" >&2
    exit 2
    ;;
esac

# JSON parse pre-check — fails fast with exit 2 on malformed context.
if command -v jq >/dev/null 2>&1; then
  if ! printf '%s' "$context_json" | jq -e . >/dev/null 2>&1; then
    err="$(printf '%s' "$context_json" | jq . 2>&1 >/dev/null || true)"
    echo "[error] render-issue-comment: malformed context JSON: ${err}" >&2
    exit 2
  fi
else
  stripped="${context_json#"${context_json%%[![:space:]]*}"}"
  stripped="${stripped%"${stripped##*[![:space:]]}"}"
  case "$stripped" in
    \{*\}) : ;;
    *)
      echo "[error] render-issue-comment: malformed context JSON (jq unavailable; expected object literal)" >&2
      exit 2
      ;;
  esac
fi

# ---------- template dir resolution ----------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${MWI_TEMPLATES_DIR:-${SCRIPT_DIR}/../references}"

use_adf=0
if [ "$backend" = "jira" ] && [ "$tier" = "rovo" ]; then
  use_adf=1
fi

if [ "$use_adf" = "1" ]; then
  template_file="${TEMPLATES_DIR}/jira-templates.md"
else
  template_file="${TEMPLATES_DIR}/github-templates.md"
fi

if [ ! -f "$template_file" ]; then
  echo "[error] render-issue-comment: template file not found: ${template_file}" >&2
  exit 1
fi

# ---------- template extraction ----------
#
# Extract the first fenced code block under the `### <type>` heading.

extract_block() {
  local file="$1" section="$2"
  awk -v target="$section" '
    BEGIN { in_section=0; in_block=0; found=0 }
    /^### / {
      hdr = substr($0, 5)
      sub(/[[:space:]]+$/, "", hdr)
      if (hdr == target) { in_section=1; in_block=0; found=0; next }
      else { in_section=0; next }
    }
    /^## / { in_section=0 }
    {
      if (in_section && !found) {
        if ($0 ~ /^```/) {
          if (in_block == 0) { in_block=1; next }
          else { in_block=0; found=1; next }
        }
        if (in_block) print
      }
    }
  ' "$file"
}

raw_block="$(extract_block "$template_file" "$type_")"

if [ -z "$raw_block" ]; then
  echo "[error] render-issue-comment: template not found for type '${type_}' in ${template_file}" >&2
  exit 1
fi

# ---------- context accessors ----------

context_get_scalar() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    local val
    val="$(printf '%s' "$context_json" \
      | jq -r --arg k "$key" 'if has($k) then (.[$k] // empty) | (if type == "string" or type == "number" or type == "boolean" then tostring else empty end) else empty end' 2>/dev/null || true)"
    printf '%s' "$val"
    return 0
  fi
  if [[ "$context_json" =~ \"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$context_json" =~ \"${key}\"[[:space:]]*:[[:space:]]*(-?[0-9]+(\.[0-9]+)?) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 0
}

context_has_key() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    local has
    has="$(printf '%s' "$context_json" | jq -r --arg k "$key" 'has($k) | tostring' 2>/dev/null || echo false)"
    [ "$has" = "true" ]
    return $?
  fi
  [[ "$context_json" =~ \"${key}\"[[:space:]]*: ]]
}

context_get_array_items() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$context_json" \
      | jq -rc --arg k "$key" 'if has($k) and (.[$k] | type == "array") then (.[$k][] | if type == "string" or type == "number" or type == "boolean" then tostring else tojson end) else empty end' 2>/dev/null \
      || true
    return 0
  fi
  if [[ "$context_json" =~ \"${key}\"[[:space:]]*:[[:space:]]*\[([^]]*)\] ]]; then
    local inner="${BASH_REMATCH[1]}"
    local tmp="$inner"
    while [[ "$tmp" =~ \"([^\"]*)\" ]]; do
      printf '%s\n' "${BASH_REMATCH[1]}"
      tmp="${tmp#*\"${BASH_REMATCH[1]}\"}"
    done
  fi
}

context_keys() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$context_json" | jq -r 'keys[]' 2>/dev/null || true
    return 0
  fi
  local s="$context_json"
  while [[ "$s" =~ \"([a-zA-Z_][a-zA-Z0-9_]*)\"[[:space:]]*: ]]; do
    printf '%s\n' "${BASH_REMATCH[1]}"
    s="${s#*\"${BASH_REMATCH[1]}\"}"
  done
}

# ---------- key normalization (markdown path) ----------

token_to_candidates() {
  local tok="$1"
  printf '%s\n' "$tok"
  local camel=""
  local first=1
  local IFS='_'
  # shellcheck disable=SC2206
  local parts=( $tok )
  for part in "${parts[@]}"; do
    local lower
    lower="$(printf '%s' "$part" | tr '[:upper:]' '[:lower:]')"
    if [ "$first" = "1" ]; then
      camel="$lower"
      first=0
    else
      local head="${lower:0:1}"
      local tail="${lower:1}"
      head="$(printf '%s' "$head" | tr '[:lower:]' '[:upper:]')"
      camel="${camel}${head}${tail}"
    fi
  done
  printf '%s\n' "$camel"
  printf '%s\n' "$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]')"
}

resolve_scalar_for_token() {
  local tok="$1"
  local cand val
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    if context_has_key "$cand"; then
      val="$(context_get_scalar "$cand")"
      if [ -n "$val" ]; then
        printf '%s' "$val"
        return 0
      fi
    fi
  done < <(token_to_candidates "$tok")
  return 0
}

resolve_list_candidate_key() {
  local tok="$1"
  local cand
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    if context_has_key "$cand"; then
      printf '%s' "$cand"
      return 0
    fi
  done < <(token_to_candidates "$tok")
  return 0
}

# ---------- markdown rendering ----------

LIST_TOKENS=(DELIVERABLES STEPS CRITERIA ROOT_CAUSES VERIFICATION_RESULTS ROOT_CAUSE_RESOLUTIONS)

is_list_token() {
  local tok="$1"
  local t
  for t in "${LIST_TOKENS[@]}"; do
    [ "$t" = "$tok" ] && return 0
  done
  return 1
}

render_markdown() {
  local body="$raw_block"
  local keys_seen=""

  # Phase 1: expand list placeholders. Use a temp file for the replacement
  # (since it contains newlines) and bash-only line iteration for the match.
  local tok
  for tok in "${LIST_TOKENS[@]}"; do
    if printf '%s' "$body" | grep -q "<${tok}>"; then
      local ctxkey
      ctxkey="$(resolve_list_candidate_key "$tok")"
      if [ -n "$ctxkey" ]; then
        keys_seen="${keys_seen} ${ctxkey}"
        local expanded=""
        local first=1
        local line
        while IFS= read -r line; do
          if [ "$first" = "1" ]; then
            expanded="- ${line}"
            first=0
          else
            expanded="${expanded}"$'\n'"- ${line}"
          fi
        done < <(context_get_array_items "$ctxkey")

        # Line-by-line walk; replace token-only lines with $expanded and
        # inline tokens with the rendered list (still multi-line).
        local new_body=""
        local first_line=1
        local cur
        while IFS= read -r cur || [ -n "$cur" ]; do
          local stripped="${cur#"${cur%%[![:space:]]*}"}"
          stripped="${stripped%"${stripped##*[![:space:]]}"}"
          local replaced="$cur"
          if [ "$stripped" = "<${tok}>" ]; then
            replaced="$expanded"
          elif [[ "$cur" == *"<${tok}>"* ]]; then
            replaced="${cur//<${tok}>/${expanded}}"
          fi
          if [ "$first_line" = "1" ]; then
            new_body="$replaced"
            first_line=0
          else
            new_body="${new_body}"$'\n'"${replaced}"
          fi
        done <<< "$body"
        body="$new_body"
      fi
    fi
  done

  # Phase 2: scalar substitution.
  local tokens_found
  tokens_found="$(printf '%s' "$body" \
    | grep -oE '<[A-Z][A-Z0-9_]*>' \
    | sort -u \
    || true)"

  local raw_tok scalar ctxkey2
  while IFS= read -r raw_tok; do
    [ -z "$raw_tok" ] && continue
    local inner="${raw_tok#<}"
    inner="${inner%>}"
    if is_list_token "$inner"; then
      continue
    fi
    scalar="$(resolve_scalar_for_token "$inner")"
    ctxkey2="$(resolve_list_candidate_key "$inner")"
    if [ -n "$ctxkey2" ]; then
      keys_seen="${keys_seen} ${ctxkey2}"
    fi
    if [ -n "$scalar" ]; then
      body="${body//${raw_tok}/${scalar}}"
    fi
  done <<< "$tokens_found"

  # Warn on unused context keys.
  local k
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    case " ${keys_seen} " in
      *" ${k} "*) ;;
      *)
        echo "[warn] render-issue-comment: unused context variable: ${k}" >&2
        ;;
    esac
  done < <(context_keys)

  # Detect unresolved placeholders.
  local remaining
  remaining="$(printf '%s' "$body" \
    | grep -oE '<[A-Z][A-Z0-9_]*>' \
    | sort -u \
    || true)"
  if [ -n "$remaining" ]; then
    local toks_list
    toks_list="$(printf '%s' "$remaining" | tr '\n' ' ' | sed 's/ $//')"
    echo "[error] render-issue-comment: unresolved placeholder(s): ${toks_list} in rendered output" >&2
    exit 1
  fi

  printf '%s' "$body"
}

# ---------- ADF rendering ----------

render_adf() {
  local body="$raw_block"
  local keys_seen=""

  if ! command -v jq >/dev/null 2>&1; then
    echo "[error] render-issue-comment: jq is required for ADF (rovo) rendering" >&2
    exit 1
  fi

  local adf
  adf="$(printf '%s' "$body" | jq -c . 2>/dev/null)" || {
    echo "[error] render-issue-comment: ADF template is not valid JSON" >&2
    exit 1
  }

  # Keys referenced by list-indexed placeholders.
  local list_keys
  list_keys="$(printf '%s' "$body" \
    | grep -oE '\{[a-zA-Z_][a-zA-Z0-9_]*\[[0-9]+\]' \
    | sed -E 's/^\{//; s/\[[0-9]+\]$//' \
    | sort -u \
    || true)"

  local lk
  while IFS= read -r lk; do
    [ -z "$lk" ] && continue
    if ! context_has_key "$lk"; then
      continue
    fi
    keys_seen="${keys_seen} ${lk}"
    local arr_json
    arr_json="$(printf '%s' "$context_json" | jq -c --arg k "$lk" '.[$k] // []')"

    adf="$(printf '%s' "$adf" | jq -c --arg lk "$lk" --argjson items "$arr_json" '
      def specialize($tpl; $val; $idx; $lk):
        $tpl | walk(
          if type == "object" and (.text // null) != null then
            (.text) as $t
            | . + { text:
                ( (
                    if ($val | type) == "object"
                      then (
                        reduce ($val | to_entries[]) as $kv ($t;
                          gsub("\\{" + $lk + "\\[" + ($idx|tostring) + "\\]\\." + $kv.key + "\\}"; ($kv.value | tostring))
                          | gsub("\\{" + $lk + "\\[0\\]\\." + $kv.key + "\\}"; ($kv.value | tostring))
                        )
                      )
                      else $t
                    end
                  )
                  | (
                      if ($val | type) != "object"
                        then (
                          gsub("\\{" + $lk + "\\[" + ($idx|tostring) + "\\]\\}"; ($val | tostring))
                          | gsub("\\{" + $lk + "\\[0\\]\\}"; ($val | tostring))
                        )
                        else .
                      end
                    )
                )
              }
          else . end
        );
      walk(
        if type == "object"
           and (.type == "bulletList" or .type == "orderedList")
           and ((tojson) | contains("{" + $lk + "["))
        then
          (.content // []) as $parent_items
          | . + { content:
              [ range(0; ($items | length)) as $idx
                | specialize($parent_items[0]; $items[$idx]; $idx; $lk)
              ]
            }
        else . end
      )
    ' 2>/dev/null)" || {
      echo "[error] render-issue-comment: ADF list expansion failed for key '${lk}'" >&2
      exit 1
    }
  done <<< "$list_keys"

  # Scalar substitution: {key}.
  local scalar_keys
  scalar_keys="$(printf '%s' "$adf" \
    | grep -oE '\{[a-zA-Z_][a-zA-Z0-9_]*\}' \
    | sed -E 's/^\{//; s/\}$//' \
    | sort -u \
    || true)"

  local sk val escaped
  while IFS= read -r sk; do
    [ -z "$sk" ] && continue
    if context_has_key "$sk"; then
      keys_seen="${keys_seen} ${sk}"
      val="$(context_get_scalar "$sk")"
      escaped="$(printf '%s' "$val" | jq -Rsc '.' 2>/dev/null || true)"
      escaped="${escaped#\"}"
      escaped="${escaped%\"}"
      adf="${adf//\{${sk}\}/${escaped}}"
    fi
  done <<< "$scalar_keys"

  # Warn on unused context keys.
  local k
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    case " ${keys_seen} " in
      *" ${k} "*) ;;
      *)
        echo "[warn] render-issue-comment: unused context variable: ${k}" >&2
        ;;
    esac
  done < <(context_keys)

  # Validate final JSON.
  if ! printf '%s' "$adf" | jq -e . >/dev/null 2>&1; then
    local verr
    verr="$(printf '%s' "$adf" | jq . 2>&1 >/dev/null || true)"
    echo "[error] render-issue-comment: rendered ADF is not valid JSON: ${verr}" >&2
    exit 1
  fi

  # Detect unresolved placeholders.
  local leftover
  leftover="$(printf '%s' "$adf" \
    | grep -oE '\{[a-zA-Z_][a-zA-Z0-9_]*(\[[0-9]+\])?(\.[a-zA-Z_][a-zA-Z0-9_]*)?\}' \
    | sort -u \
    || true)"
  if [ -n "$leftover" ]; then
    local toks_list
    toks_list="$(printf '%s' "$leftover" | tr '\n' ' ' | sed 's/ $//')"
    echo "[error] render-issue-comment: unresolved placeholder(s): ${toks_list} in rendered output" >&2
    exit 1
  fi

  printf '%s' "$adf" | jq .
}

# ---------- dispatch ----------

if [ "$use_adf" = "1" ]; then
  render_adf
else
  render_markdown
fi
