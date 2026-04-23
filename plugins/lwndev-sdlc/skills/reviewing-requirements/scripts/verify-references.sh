#!/usr/bin/env bash
# verify-references.sh — Verify extracted references against the codebase and
# GitHub (FEAT-026 / FR-3).
#
# Consumes the JSON output shape produced by `extract-references.sh`:
#   {"filePaths":[...],"identifiers":[...],"crossRefs":[...],"ghRefs":[...]}
#
# Emits a classification object with five arrays, all always present:
#   {"ok":[...],"moved":[...],"ambiguous":[...],"missing":[...],"unavailable":[...]}
# Each entry is {"category":"filePaths","ref":"...","detail":"..."}.
#
# Classification strategies by category:
#   filePaths   — `test -e`; basename fallback via `git ls-files | grep -F`.
#                 Buckets: ok / moved / ambiguous / missing.
#   identifiers — `git grep -n <id>` across tracked files. Buckets:
#                 ok (1..19 matches) / ambiguous (>=20) / missing (0).
#   crossRefs   — `ls requirements/{features,chores,bugs}/<REF>-*.md`.
#                 Buckets: ok / ambiguous / missing.
#   ghRefs      — `gh issue view <N> --json number,state`. Buckets:
#                 ok / missing (404) / unavailable (gh missing / unauth /
#                 non-404 error). One `[info]` line per invocation when any
#                 ghRef is marked unavailable, not one per ref.
#
# Usage:
#   verify-references.sh <refs-json>
#
# <refs-json> dual-shape dispatch:
#   * First non-whitespace char is `{` or `[` -> treated as literal JSON.
#   * Otherwise treated as a file path; if the file doesn't exist, the arg is
#     re-treated as a literal JSON string.
#
# Exit codes:
#   0  success (including graceful `gh` skip)
#   1  unparseable JSON
#   2  missing arg
#
# Dependencies:
#   bash, git, grep, ls. `gh` optional (graceful skip if missing /
#   unauthenticated). `jq` is optional — used for JSON parsing and assembly
#   when available; pure-bash fallback otherwise.

set -euo pipefail

# --- Argument handling --------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "[error] usage: verify-references.sh <refs-json>" >&2
  exit 2
fi

RAW_ARG="$1"

# Dispatch: JSON literal vs file path.
# Strip leading whitespace to inspect the first non-whitespace char.
stripped_arg="${RAW_ARG#"${RAW_ARG%%[![:space:]]*}"}"
first_char="${stripped_arg:0:1}"

if [[ "$first_char" == "{" || "$first_char" == "[" ]]; then
  JSON_INPUT="$RAW_ARG"
elif [[ -f "$RAW_ARG" && -r "$RAW_ARG" ]]; then
  JSON_INPUT=$(cat "$RAW_ARG")
else
  # Fallback: treat the arg itself as JSON (may still fail parse -> exit 1).
  JSON_INPUT="$RAW_ARG"
fi

HAS_JQ=0
if command -v jq >/dev/null 2>&1; then
  HAS_JQ=1
fi

# --- JSON parsing -------------------------------------------------------------
# Attempt to validate and extract the four arrays.

parse_with_jq() {
  # Produces four newline-separated lists prefixed with an anchor tag.
  if ! printf '%s' "$JSON_INPUT" | jq -e . >/dev/null 2>&1; then
    return 1
  fi
  # Normalize: extract each array, tolerant of missing keys.
  FILE_PATHS=$(printf '%s' "$JSON_INPUT" | jq -r '.filePaths[]? // empty')
  IDENTIFIERS=$(printf '%s' "$JSON_INPUT" | jq -r '.identifiers[]? // empty')
  CROSS_REFS=$(printf '%s' "$JSON_INPUT" | jq -r '.crossRefs[]? // empty')
  GH_REFS=$(printf '%s' "$JSON_INPUT" | jq -r '.ghRefs[]? // empty')
  return 0
}

parse_without_jq() {
  # Best-effort pure-bash parser for the single-line shape produced by
  # extract-references.sh. Accepts missing keys.
  local input="$JSON_INPUT"
  # Quick validity gate: must contain a `{` and a matching `}`.
  if [[ "$input" != *"{"* || "$input" != *"}"* ]]; then
    return 1
  fi
  _extract_array() {
    local key="$1"
    local content="$2"
    # Grab substring after `"$key":[` up to the next `]`. Using sed.
    printf '%s' "$content" \
      | sed -n "s/.*\"${key}\":\\[\\([^]]*\\)\\].*/\\1/p" \
      | tr ',' '\n' \
      | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' \
      | awk 'NF > 0 || /""/' \
      | awk '!/^$/'
  }
  FILE_PATHS=$(_extract_array filePaths "$input" || true)
  IDENTIFIERS=$(_extract_array identifiers "$input" || true)
  CROSS_REFS=$(_extract_array crossRefs "$input" || true)
  GH_REFS=$(_extract_array ghRefs "$input" || true)
  return 0
}

if [[ "$HAS_JQ" -eq 1 ]]; then
  if ! parse_with_jq; then
    echo "[error] verify-references: cannot parse JSON input." >&2
    exit 1
  fi
else
  if ! parse_without_jq; then
    echo "[error] verify-references: cannot parse JSON input." >&2
    exit 1
  fi
fi

# --- Classification buckets ---------------------------------------------------
# Each line: category|ref|detail
OK_LINES=""
MOVED_LINES=""
AMBIGUOUS_LINES=""
MISSING_LINES=""
UNAVAILABLE_LINES=""

append_line() {
  # $1 = bucket-var-name, $2 = category, $3 = ref, $4 = detail
  local var="$1" cat="$2" ref="$3" detail="$4"
  local line="${cat}|${ref}|${detail}"
  printf -v "$var" '%s%s\n' "${!var}" "$line"
}

# --- filePaths verification ---------------------------------------------------

have_git=0
if command -v git >/dev/null 2>&1; then
  have_git=1
fi

git_ls_files_cache=""
if [[ "$have_git" -eq 1 ]]; then
  git_ls_files_cache=$(git ls-files 2>/dev/null || true)
fi

verify_file_path() {
  local path="$1"
  if [[ -z "$path" ]]; then return; fi
  if [[ -e "$path" ]]; then
    append_line OK_LINES "filePaths" "$path" "exact path exists"
    return
  fi
  local basename="${path##*/}"
  local matches=""
  if [[ "$have_git" -eq 1 && -n "$git_ls_files_cache" ]]; then
    matches=$(printf '%s\n' "$git_ls_files_cache" | grep -F -- "$basename" || true)
    # Reduce to lines where the terminal segment equals the basename.
    if [[ -n "$matches" ]]; then
      matches=$(printf '%s\n' "$matches" | awk -v bn="$basename" '{
        n = split($0, parts, "/")
        if (parts[n] == bn) print
      }')
    fi
  fi

  if [[ -z "$matches" ]]; then
    append_line MISSING_LINES "filePaths" "$path" "no file with basename ${basename} tracked in git"
    return
  fi

  local count
  count=$(printf '%s\n' "$matches" | awk 'NF > 0' | wc -l | tr -d ' ')

  if [[ "$count" -eq 1 ]]; then
    local alt
    alt=$(printf '%s' "$matches" | head -n1)
    append_line MOVED_LINES "filePaths" "$path" "basename match at ${alt} (was ${path})"
  else
    local joined
    joined=$(printf '%s' "$matches" | tr '\n' ',' | sed -e 's/,$//')
    append_line AMBIGUOUS_LINES "filePaths" "$path" "multiple basename matches: ${joined}"
  fi
}

while IFS= read -r fp; do
  [[ -z "$fp" ]] && continue
  verify_file_path "$fp"
done <<< "$FILE_PATHS"

# --- identifiers verification -------------------------------------------------

verify_identifier() {
  local id="$1"
  if [[ -z "$id" ]]; then return; fi
  local count=0
  if [[ "$have_git" -eq 1 ]]; then
    # `git grep -cF` would collapse to file-count; we want line-count. Use
    # `git grep -nF` and count non-empty lines. Use `-F` for literal match so
    # identifier-shaped strings do not become regex.
    local matches
    matches=$(git grep -nF -- "$id" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
      count=$(printf '%s\n' "$matches" | awk 'NF > 0' | wc -l | tr -d ' ')
    fi
  fi

  if [[ "$count" -eq 0 ]]; then
    append_line MISSING_LINES "identifiers" "$id" "no matches in tracked files"
  elif [[ "$count" -ge 20 ]]; then
    append_line AMBIGUOUS_LINES "identifiers" "$id" "${count} matches (>=20, too generic to verify)"
  else
    append_line OK_LINES "identifiers" "$id" "${count} match(es)"
  fi
}

while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  verify_identifier "$id"
done <<< "$IDENTIFIERS"

# --- crossRefs verification ---------------------------------------------------

verify_cross_ref() {
  local ref="$1"
  local subdir=""
  case "$ref" in
    FEAT-*) subdir="features" ;;
    CHORE-*) subdir="chores" ;;
    BUG-*) subdir="bugs" ;;
    *) return ;;
  esac
  local matches=()
  while IFS= read -r match; do
    [[ -n "$match" ]] && matches+=("$match")
  done < <(compgen -G "requirements/${subdir}/${ref}-*.md" 2>/dev/null || true)

  local count=${#matches[@]}
  if [[ "$count" -eq 1 ]]; then
    append_line OK_LINES "crossRefs" "$ref" "${matches[0]}"
  elif [[ "$count" -eq 0 ]]; then
    append_line MISSING_LINES "crossRefs" "$ref" "no file matching requirements/${subdir}/${ref}-*.md"
  else
    local joined
    joined=$(IFS=,; echo "${matches[*]}")
    append_line AMBIGUOUS_LINES "crossRefs" "$ref" "multiple matches: ${joined}"
  fi
}

while IFS= read -r cr; do
  [[ -z "$cr" ]] && continue
  verify_cross_ref "$cr"
done <<< "$CROSS_REFS"

# --- ghRefs verification ------------------------------------------------------
# gh-availability is checked once per invocation. When unavailable, all ghRefs
# get classified as `unavailable` and we emit a single `[info]` line.

gh_available=0
gh_auth_rc=1
if command -v gh >/dev/null 2>&1; then
  gh_available=1
  if gh auth status >/dev/null 2>&1; then
    gh_auth_rc=0
  fi
fi

gh_unavailable_refs=()
gh_unavailable_reason=""

verify_gh_ref() {
  local ref="$1"
  # Only handle bare #N; non-origin URLs pass through as unavailable (we can't
  # resolve them without knowing the owner/repo).
  if [[ ! "$ref" =~ ^#([0-9]+)$ ]]; then
    gh_unavailable_refs+=("$ref")
    gh_unavailable_reason="non-#N reference (full URL); cannot resolve without repo context"
    return
  fi
  local num="${BASH_REMATCH[1]}"

  if [[ "$gh_available" -ne 1 ]]; then
    gh_unavailable_refs+=("$ref")
    gh_unavailable_reason="gh CLI not on PATH"
    return
  fi
  if [[ "$gh_auth_rc" -ne 0 ]]; then
    gh_unavailable_refs+=("$ref")
    gh_unavailable_reason="gh not authenticated"
    return
  fi

  local out err rc
  err_tmp=$(mktemp)
  if out=$(gh issue view "$num" --json number,state 2>"$err_tmp"); then
    append_line OK_LINES "ghRefs" "$ref" "issue exists"
    rm -f "$err_tmp"
  else
    rc=$?
    err=$(cat "$err_tmp" 2>/dev/null || true)
    rm -f "$err_tmp"
    # Detect 404 / not-found -> missing. Otherwise unavailable.
    if [[ "$err" == *"not found"* || "$err" == *"404"* || "$err" == *"Not Found"* || "$err" == *"Could not resolve"* ]]; then
      append_line MISSING_LINES "ghRefs" "$ref" "issue not found (404)"
    else
      gh_unavailable_refs+=("$ref")
      gh_unavailable_reason="gh issue view failed: ${err:-rc=$rc}"
    fi
  fi
}

while IFS= read -r gr; do
  [[ -z "$gr" ]] && continue
  verify_gh_ref "$gr"
done <<< "$GH_REFS"

if [[ "${#gh_unavailable_refs[@]}" -gt 0 ]]; then
  # Emit ONE [info] line per invocation.
  echo "[info] verify-references: gh unavailable; ${#gh_unavailable_refs[@]} ghRefs marked unavailable." >&2
  for ref in "${gh_unavailable_refs[@]}"; do
    append_line UNAVAILABLE_LINES "ghRefs" "$ref" "$gh_unavailable_reason"
  done
fi

# --- JSON assembly ------------------------------------------------------------

emit_entries_array() {
  # Reads lines of shape `<category>|<ref>|<detail>` and emits a JSON array of
  # {category, ref, detail} objects. Uses jq when available.
  if [[ "$HAS_JQ" -eq 1 ]]; then
    jq -Rs '
      split("\n")
      | map(select(length > 0))
      | map(
          (split("|")) as $parts
          | {category: ($parts[0] // ""),
             ref: ($parts[1] // ""),
             detail: ($parts[2] // "")}
        )
    '
  else
    local first=1
    printf '['
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local cat ref detail rest
      cat="${line%%|*}"
      rest="${line#*|}"
      ref="${rest%%|*}"
      if [[ "$rest" == *"|"* ]]; then
        detail="${rest#*|}"
      else
        detail=""
      fi
      if [[ "$first" -eq 1 ]]; then first=0; else printf ','; fi
      local esc
      esc="${detail//\\/\\\\}"
      esc="${esc//\"/\\\"}"
      esc="${esc//$'\t'/\\t}"
      esc="${esc//$'\r'/\\r}"
      esc="${esc//$'\n'/\\n}"
      printf '{"category":"%s","ref":"%s","detail":"%s"}' "$cat" "$ref" "$esc"
    done
    printf ']'
  fi
}

arr_ok=$(printf '%s' "$OK_LINES" | emit_entries_array)
arr_moved=$(printf '%s' "$MOVED_LINES" | emit_entries_array)
arr_amb=$(printf '%s' "$AMBIGUOUS_LINES" | emit_entries_array)
arr_miss=$(printf '%s' "$MISSING_LINES" | emit_entries_array)
arr_unavail=$(printf '%s' "$UNAVAILABLE_LINES" | emit_entries_array)

if [[ "$HAS_JQ" -eq 1 ]]; then
  jq -cn \
    --argjson ok "$arr_ok" \
    --argjson moved "$arr_moved" \
    --argjson amb "$arr_amb" \
    --argjson miss "$arr_miss" \
    --argjson unavail "$arr_unavail" \
    '{ok: $ok, moved: $moved, ambiguous: $amb, missing: $miss, unavailable: $unavail}'
else
  printf '{"ok":%s,"moved":%s,"ambiguous":%s,"missing":%s,"unavailable":%s}\n' \
    "$arr_ok" "$arr_moved" "$arr_amb" "$arr_miss" "$arr_unavail"
fi
