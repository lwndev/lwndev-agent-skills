#!/usr/bin/env bash
# pr-diff-vs-plan.sh — PR diff vs test-plan drift detector (FEAT-026 / FR-6).
#
# Fetches the unified diff for a pull request via `gh pr diff <N>` and flags
# any test-plan references that align with changed / deleted / renamed files
# or changed function/class/interface/type signatures.
#
# Output shape (all three arrays always present):
#   {"flaggedFiles":[...],"flaggedIdentifiers":[...],"flaggedSignatures":[...]}
# Each entry:
#   {"testPlanLine":N,"scenarioSnippet":"...","drift":"deleted|renamed|signature-changed|content-changed","detail":"..."}
#
# Graceful degradation: if `gh` is not on PATH, emit a `[warn] gh CLI not
# found — ...` line to stderr and exit `0` with empty stdout. If `gh pr diff`
# itself fails, emit `[warn] gh pr diff failed: <err>. Skipping ...` to stderr
# and exit `0` with empty stdout.
#
# Usage:
#   pr-diff-vs-plan.sh <pr-number> <test-plan>
#
# Exit codes:
#   0  success (including graceful skip paths)
#   1  unreadable test-plan file
#   2  missing args; malformed pr-number (non-integer, negative, zero, float,
#      hex)
#
# Dependencies:
#   bash, grep, awk. `gh` optional — graceful skip if missing. `jq` is optional
#   — used for JSON assembly when available; falls back to pure-bash printf
#   construction otherwise.

set -euo pipefail

# --- Argument handling --------------------------------------------------------

if [[ $# -lt 2 ]]; then
  echo "[error] usage: pr-diff-vs-plan.sh <pr-number> <test-plan>" >&2
  exit 2
fi

PR_NUM="$1"
TEST_PLAN="$2"

if [[ -z "$PR_NUM" || -z "$TEST_PLAN" ]]; then
  echo "[error] usage: pr-diff-vs-plan.sh <pr-number> <test-plan>" >&2
  exit 2
fi

# pr-number must be a positive integer: no sign, no leading zero except `0`
# itself (but zero is not a valid PR), no float, no hex prefix.
if [[ ! "$PR_NUM" =~ ^[1-9][0-9]*$ ]]; then
  echo "[error] pr-diff-vs-plan: <pr-number> must be a positive integer (got '${PR_NUM}')" >&2
  exit 2
fi

if [[ ! -r "$TEST_PLAN" || ! -f "$TEST_PLAN" ]]; then
  echo "[error] pr-diff-vs-plan: cannot read test-plan: ${TEST_PLAN}" >&2
  exit 1
fi

HAS_JQ=0
if command -v jq >/dev/null 2>&1; then
  HAS_JQ=1
fi

# --- gh availability ----------------------------------------------------------

if ! command -v gh >/dev/null 2>&1; then
  echo "[warn] gh CLI not found — cannot fetch PR diff. Skipping pr-diff-vs-plan check." >&2
  exit 0
fi

# --- Fetch PR diff ------------------------------------------------------------

_diff_err_tmp=$(mktemp)
if ! DIFF=$(gh pr diff "$PR_NUM" 2>"$_diff_err_tmp"); then
  _err_text=$(cat "$_diff_err_tmp" 2>/dev/null || true)
  rm -f "$_diff_err_tmp"
  # Trim the error text to the first line for the [warn].
  _err_line=$(printf '%s' "$_err_text" | head -n 1)
  echo "[warn] gh pr diff failed: ${_err_line:-unknown error}. Skipping pr-diff-vs-plan check." >&2
  exit 0
fi
rm -f "$_diff_err_tmp"

# --- Parse the diff -----------------------------------------------------------
# Produce four newline-separated lists:
#   DIFF_CHANGED_FILES   — file paths with any hunk (added or removed content).
#   DIFF_DELETED_FILES   — file paths whose header contains `deleted file mode`.
#   DIFF_RENAMED_PAIRS   — "old -> new" pairs from `rename from/to` blocks.
#   DIFF_SIG_IDS         — identifier tokens whose containing function/class/
#                          interface/type signature changed.

DIFF_CHANGED_FILES=""
DIFF_DELETED_FILES=""
DIFF_RENAMED_PAIRS=""
DIFF_SIG_IDS=""

# Parse with awk for clarity; emit tag-prefixed lines we then sort into lists.
_parsed=$(printf '%s\n' "$DIFF" | awk '
  BEGIN {
    current_old=""; current_new=""; deleted=0; renamed_from=""; renamed_to=""
  }
  # `diff --git a/<old> b/<new>` opens a per-file block.
  /^diff --git / {
    # Flush state from the previous block.
    if (renamed_from != "" && renamed_to != "") {
      printf "RENAMED\t%s\t%s\n", renamed_from, renamed_to
    }
    if (deleted && current_old != "") {
      printf "DELETED\t%s\n", current_old
    }
    current_old=""; current_new=""; deleted=0; renamed_from=""; renamed_to=""
    # Extract old/new from header.
    if (match($0, /a\/[^ ]+ b\/[^ ]+$/)) {
      header=substr($0, RSTART, RLENGTH)
      split(header, parts, " ")
      ao=parts[1]; bn=parts[2]
      sub(/^a\//, "", ao); sub(/^b\//, "", bn)
      current_old=ao; current_new=bn
    }
    next
  }
  /^deleted file mode/ { deleted=1; next }
  /^rename from / { renamed_from=$3; next }
  /^rename to /   { renamed_to=$3; next }
  # `+++ b/<path>` marks the target of a content-changed file.
  /^\+\+\+ b\// {
    p=substr($0, 7)
    if (p != "/dev/null") {
      printf "CHANGED\t%s\n", p
    }
    next
  }
  # Signature detection on added / removed lines. POSIX regex (no \< word
  # boundary). We first strip the leading +/- and anchor on beginning-of-line
  # or whitespace to avoid false positives on tokens like `myfunction`.
  /^[+-][^+-]/ {
    line=$0
    sub(/^[+-]/, "", line)
    sig_match=0
    if (line ~ /(^|[[:space:]])function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(/) sig_match=1
    if (line ~ /(^|[[:space:]])(class|interface|type)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[=({]/) sig_match=1
    if (sig_match) {
      if (match(line, /function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
        tok=substr(line, RSTART, RLENGTH)
        sub(/^function[[:space:]]+/, "", tok)
        printf "SIGID\t%s\n", tok
      }
      if (match(line, /(class|interface|type)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
        tok=substr(line, RSTART, RLENGTH)
        sub(/^(class|interface|type)[[:space:]]+/, "", tok)
        printf "SIGID\t%s\n", tok
      }
    }
  }
  END {
    if (renamed_from != "" && renamed_to != "") {
      printf "RENAMED\t%s\t%s\n", renamed_from, renamed_to
    }
    if (deleted && current_old != "") {
      printf "DELETED\t%s\n", current_old
    }
  }
')

while IFS=$'\t' read -r _tag _a _b; do
  case "$_tag" in
    CHANGED)  DIFF_CHANGED_FILES+="${_a}"$'\n' ;;
    DELETED)  DIFF_DELETED_FILES+="${_a}"$'\n' ;;
    RENAMED)  DIFF_RENAMED_PAIRS+="${_a}|${_b}"$'\n' ;;
    SIGID)    DIFF_SIG_IDS+="${_a}"$'\n' ;;
  esac
done <<< "$_parsed"

# De-duplicate preserving order.
_dedup() { awk '!seen[$0]++'; }
DIFF_CHANGED_FILES=$(printf '%s' "$DIFF_CHANGED_FILES" | _dedup)
DIFF_DELETED_FILES=$(printf '%s' "$DIFF_DELETED_FILES" | _dedup)
DIFF_RENAMED_PAIRS=$(printf '%s' "$DIFF_RENAMED_PAIRS" | _dedup)
DIFF_SIG_IDS=$(printf '%s' "$DIFF_SIG_IDS" | _dedup)

# --- Parse the test plan for references ---------------------------------------
# We reuse the FR-2 extraction patterns inline: file paths and identifiers.
# For each match we track the line number so we can attribute drift.

# Collect (lineno, filepath) pairs.
TEST_PLAN_FILES=""    # "lineno|path"
TEST_PLAN_IDENTS=""   # "lineno|identifier"

_is_ident_kw() {
  case "$1" in
    true|false|null|undefined|None|True|False|NULL) return 0 ;;
    if|else|elif|for|while|do|done|return|break|continue) return 0 ;;
    const|let|var|function|class|import|export|default|type|interface|enum) return 0 ;;
    public|private|protected|static|abstract|async|await|yield|new|this|super) return 0 ;;
    try|catch|finally|throw|throws|switch|case) return 0 ;;
    in|of|is|as|from|with|not|and|or) return 0 ;;
    *) return 1 ;;
  esac
}

_plan_line_no=0
while IFS= read -r _tp_line; do
  _plan_line_no=$((_plan_line_no + 1))
  # File paths matching the FR-2 regex.
  while IFS= read -r _fp; do
    [[ -z "$_fp" ]] && continue
    TEST_PLAN_FILES+="${_plan_line_no}|${_fp}"$'\n'
  done < <(printf '%s\n' "$_tp_line" | grep -oE '[A-Za-z0-9_./-]+\.(md|ts|tsx|js|jsx|json|sh|bats|ya?ml|toml)' || true)
  # Backticked identifiers matching ^[a-zA-Z_$][a-zA-Z0-9_$]*$, length > 1,
  # not a keyword.
  while IFS= read -r _bt; do
    [[ -z "$_bt" ]] && continue
    local_tok="${_bt#\`}"
    local_tok="${local_tok%\`}"
    if [[ ${#local_tok} -le 1 ]]; then continue; fi
    if [[ ! "$local_tok" =~ ^[a-zA-Z_\$][a-zA-Z0-9_\$]*$ ]]; then continue; fi
    if _is_ident_kw "$local_tok"; then continue; fi
    TEST_PLAN_IDENTS+="${_plan_line_no}|${local_tok}"$'\n'
  done < <(printf '%s\n' "$_tp_line" | grep -oE '`[^`]+`' || true)
done < "$TEST_PLAN"

# Dedupe (by full "lineno|value" key — multiple hits on the same line collapse
# to one entry).
TEST_PLAN_FILES=$(printf '%s' "$TEST_PLAN_FILES" | _dedup)
TEST_PLAN_IDENTS=$(printf '%s' "$TEST_PLAN_IDENTS" | _dedup)

# --- Drift classification -----------------------------------------------------
# Emit <lineno>\t<scenarioSnippet>\t<drift>\t<detail> lines into three buckets.

FLAGGED_FILES=""         # file drift class (deleted / renamed / content-changed)
FLAGGED_IDENTIFIERS=""   # identifier mentions with signature-changed class
FLAGGED_SIGNATURES=""    # signature-changed class (same identifier set)

# The diff lookup data is held as newline-separated strings (bash 3.2
# + set -u friendly; consistent with verify-references.sh pattern).
#   _CHANGED   — newline-joined changed file paths
#   _DELETED   — newline-joined deleted file paths
#   _RENAMED   — newline-joined "old|new" pairs
_CHANGED="$DIFF_CHANGED_FILES"
_DELETED="$DIFF_DELETED_FILES"
_RENAMED="$DIFF_RENAMED_PAIRS"

_SIG_IDS_SET=$(printf '%s' "$DIFF_SIG_IDS" | awk 'NF' | awk '!seen[$0]++')
_sig_has() {
  # $1 = identifier
  [[ -z "$_SIG_IDS_SET" ]] && return 1
  printf '%s\n' "$_SIG_IDS_SET" | grep -Fxq -- "$1"
}

# Fetch a snippet for a given plan line number.
_plan_snippet() {
  local n="$1"
  sed -n "${n}p" "$TEST_PLAN" | head -c 120
}

append_flag() {
  # $1 bucket-var, $2 lineno, $3 snippet, $4 drift, $5 detail
  local var="$1" lineno="$2" snippet="$3" drift="$4" detail="$5"
  # Compact snippet: collapse whitespace and escape tabs.
  snippet=$(printf '%s' "$snippet" | tr '\t' ' ' | tr -s ' ')
  printf -v "$var" '%s%s\n' "${!var}" "${lineno}"$'\t'"${snippet}"$'\t'"${drift}"$'\t'"${detail}"
}

# File drift.
while IFS= read -r _tp_rec; do
  [[ -z "$_tp_rec" ]] && continue
  _lineno="${_tp_rec%%|*}"
  _path="${_tp_rec#*|}"
  [[ -z "$_path" ]] && continue
  _snippet=$(_plan_snippet "$_lineno")

  _matched=0
  # Deleted?
  while IFS= read -r _df; do
    [[ -z "$_df" ]] && continue
    if [[ "$_df" == "$_path" || "$_df" == *"/$_path" || "$_path" == *"/$_df" ]]; then
      append_flag FLAGGED_FILES "$_lineno" "$_snippet" "deleted" "test-plan references deleted path ${_df}"
      _matched=1
      break
    fi
  done <<< "$_DELETED"
  [[ "$_matched" -eq 1 ]] && continue

  # Renamed?
  while IFS= read -r _p; do
    [[ -z "$_p" ]] && continue
    _rf="${_p%%|*}"
    _rt="${_p##*|}"
    if [[ "$_rf" == "$_path" || "$_path" == *"/$_rf" ]]; then
      append_flag FLAGGED_FILES "$_lineno" "$_snippet" "renamed" "test-plan path ${_path} renamed: ${_rf} -> ${_rt}"
      _matched=1
      break
    fi
  done <<< "$_RENAMED"
  [[ "$_matched" -eq 1 ]] && continue

  # Content-changed?
  while IFS= read -r _cf; do
    [[ -z "$_cf" ]] && continue
    if [[ "$_cf" == "$_path" || "$_cf" == *"/$_path" || "$_path" == *"/$_cf" ]]; then
      append_flag FLAGGED_FILES "$_lineno" "$_snippet" "content-changed" "test-plan path ${_path} content changed in PR diff"
      break
    fi
  done <<< "$_CHANGED"
done <<< "$TEST_PLAN_FILES"

# Identifier / signature drift.
while IFS= read -r _tp_rec; do
  [[ -z "$_tp_rec" ]] && continue
  _lineno="${_tp_rec%%|*}"
  _id="${_tp_rec#*|}"
  [[ -z "$_id" ]] && continue
  _snippet=$(_plan_snippet "$_lineno")

  if _sig_has "$_id"; then
    append_flag FLAGGED_SIGNATURES "$_lineno" "$_snippet" "signature-changed" "test-plan identifier ${_id} has a changed signature in PR diff"
    append_flag FLAGGED_IDENTIFIERS "$_lineno" "$_snippet" "signature-changed" "test-plan identifier ${_id} appears in a changed signature"
  fi
done <<< "$TEST_PLAN_IDENTS"

# --- JSON assembly ------------------------------------------------------------

emit_flag_array() {
  if [[ "$HAS_JQ" -eq 1 ]]; then
    jq -Rs '
      split("\n")
      | map(select(length > 0))
      | map(
          (split("\t")) as $parts
          | {testPlanLine: (($parts[0] // "0") | tonumber? // 0),
             scenarioSnippet: ($parts[1] // ""),
             drift: ($parts[2] // ""),
             detail: ($parts[3] // "")}
        )
    '
  else
    local first=1
    printf '['
    while IFS=$'\t' read -r lineno snippet drift detail; do
      [[ -z "$lineno" ]] && continue
      if [[ "$first" -eq 1 ]]; then first=0; else printf ','; fi
      local esc_snip esc_detail
      esc_snip="${snippet//\\/\\\\}"; esc_snip="${esc_snip//\"/\\\"}"
      esc_detail="${detail//\\/\\\\}"; esc_detail="${esc_detail//\"/\\\"}"
      printf '{"testPlanLine":%s,"scenarioSnippet":"%s","drift":"%s","detail":"%s"}' \
        "$lineno" "$esc_snip" "$drift" "$esc_detail"
    done
    printf ']'
  fi
}

arr_files=$(printf '%s' "$FLAGGED_FILES" | emit_flag_array)
arr_idents=$(printf '%s' "$FLAGGED_IDENTIFIERS" | emit_flag_array)
arr_sigs=$(printf '%s' "$FLAGGED_SIGNATURES" | emit_flag_array)

if [[ "$HAS_JQ" -eq 1 ]]; then
  jq -cn \
    --argjson f "$arr_files" \
    --argjson i "$arr_idents" \
    --argjson s "$arr_sigs" \
    '{flaggedFiles: $f, flaggedIdentifiers: $i, flaggedSignatures: $s}'
else
  printf '{"flaggedFiles":%s,"flaggedIdentifiers":%s,"flaggedSignatures":%s}\n' \
    "$arr_files" "$arr_idents" "$arr_sigs"
fi
