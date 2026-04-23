#!/usr/bin/env bash
# extract-references.sh — Extract reference-shaped tokens from a requirement doc
# (FEAT-026 / FR-2).
#
# Scans the supplied markdown document for four reference classes and emits a
# single JSON object on stdout. All four arrays are always present (possibly
# empty). Entries are de-duplicated preserving first-occurrence order.
#
# Reference classes:
#   filePaths   — tokens matching
#                   [A-Za-z0-9_./-]+\.(md|ts|tsx|js|jsx|json|sh|bats|ya?ml|toml)
#                 inside backticks or as bare paths.
#   identifiers — backticked tokens matching ^[a-zA-Z_$][a-zA-Z0-9_$]*$ that
#                 plausibly name a function, class, or exported symbol. Skips
#                 common false positives: true/false/null, single-letter names,
#                 and common language keywords.
#   crossRefs   — every FEAT-/CHORE-/BUG-[0-9]+ token.
#   ghRefs      — every #[0-9]+ token plus
#                   https://github.com/<owner>/<repo>/(issues|pull)/[0-9]+ URLs.
#                 When the URL's owner/repo matches `git remote get-url origin`,
#                 the URL is normalized to #<N>. Otherwise the full URL is kept.
#
# Usage:
#   extract-references.sh <doc-path>
#
# Exit codes:
#   0  success
#   1  file does not exist / is unreadable
#   2  missing arg
#
# Dependencies:
#   bash, grep, awk (POSIX). `jq` is optional — used for JSON assembly when
#   available; falls back to pure-bash printf construction otherwise.

set -euo pipefail

# --- Argument handling --------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "[error] usage: extract-references.sh <doc-path>" >&2
  exit 2
fi

DOC_PATH="$1"

if [[ ! -r "$DOC_PATH" || ! -f "$DOC_PATH" ]]; then
  echo "[error] extract-references: cannot read file: ${DOC_PATH}" >&2
  exit 1
fi

# --- Helpers ------------------------------------------------------------------

# Deduplicate lines preserving first-occurrence order.
dedupe_stable() {
  awk '!seen[$0]++'
}

# Keyword / false-positive filter for identifiers.
is_identifier_keyword() {
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

# Emit a JSON array from a list of newline-separated strings. Uses jq when
# present; otherwise escapes by hand.
emit_json_array() {
  if command -v jq >/dev/null 2>&1; then
    # jq -R reads each raw input line as a string; slurp into an array.
    # An empty input yields an empty array.
    jq -Rs 'split("\n") | map(select(length > 0))'
  else
    local first=1
    printf '['
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ "$first" -eq 1 ]]; then
        first=0
      else
        printf ','
      fi
      # JSON-escape: backslash, double-quote, control chars.
      local esc
      esc="${line//\\/\\\\}"
      esc="${esc//\"/\\\"}"
      esc="${esc//$'\t'/\\t}"
      esc="${esc//$'\r'/\\r}"
      esc="${esc//$'\n'/\\n}"
      printf '"%s"' "$esc"
    done
    printf ']'
  fi
}

# --- Origin detection (best effort, for ghRef URL normalization) --------------
ORIGIN_OWNER=""
ORIGIN_REPO=""
if command -v git >/dev/null 2>&1; then
  origin_url=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ -n "$origin_url" ]]; then
    # Strip trailing .git if present.
    origin_url="${origin_url%.git}"
    # Support both https and ssh shapes.
    #   https://github.com/<owner>/<repo>
    #   git@github.com:<owner>/<repo>
    if [[ "$origin_url" =~ github\.com[:/]+([^/]+)/([^/]+)$ ]]; then
      ORIGIN_OWNER="${BASH_REMATCH[1]}"
      ORIGIN_REPO="${BASH_REMATCH[2]}"
    fi
  fi
fi

# --- Extraction --------------------------------------------------------------

# We read the whole file into a single variable for multi-pattern scanning.
CONTENT=$(cat "$DOC_PATH")

# `grep -oE` exits 1 on zero matches; absorb that under set -e / pipefail.
grep_or_empty() {
  grep -oE "$@" || true
}

# 1) filePaths: pattern matches a path-like token ending with a known extension.
#    We use grep -oE with a generous character class then filter.
file_paths=$(
  printf '%s\n' "$CONTENT" \
    | grep_or_empty '[A-Za-z0-9_./-]+\.(md|ts|tsx|js|jsx|json|sh|bats|ya?ml|toml)' \
    | awk '
      {
        # Skip tokens that are purely numeric-with-dots (version strings
        # masquerading as a path with .toml / .json / etc. — unlikely but
        # guard anyway). File paths in practice always contain letters.
        if ($0 ~ /^[0-9.]+$/) next
        print
      }
    ' \
    | dedupe_stable
)

# 2) identifiers: backticked tokens matching a programming identifier shape.
#    Pull every backticked run, then filter by regex + keyword list.
identifiers=$(
  printf '%s\n' "$CONTENT" \
    | grep_or_empty '`[^`]+`' \
    | sed -e 's/^`//' -e 's/`$//' \
    | while IFS= read -r tok; do
        # Identifier shape only; skip empty / keywords / single-letter.
        if [[ ${#tok} -le 1 ]]; then continue; fi
        if [[ ! "$tok" =~ ^[a-zA-Z_$][a-zA-Z0-9_$]*$ ]]; then continue; fi
        if is_identifier_keyword "$tok"; then continue; fi
        printf '%s\n' "$tok"
      done \
    | dedupe_stable
)

# 3) crossRefs: FEAT-/CHORE-/BUG- followed by digits.
cross_refs=$(
  printf '%s\n' "$CONTENT" \
    | grep_or_empty '(FEAT|CHORE|BUG)-[0-9]+' \
    | dedupe_stable
)

# 4) ghRefs: #[0-9]+ and https://github.com/<owner>/<repo>/(issues|pull)/<N>.
#    Full URLs are processed first so a URL that matches origin is normalized
#    and a URL that does not match origin emits the full URL. Bare #N shorthands
#    come second. All collected then de-duplicated preserving order.
gh_refs=$(
  {
    printf '%s\n' "$CONTENT" \
      | grep_or_empty 'https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/(issues|pull)/[0-9]+' \
      | while IFS= read -r url; do
          [[ -z "$url" ]] && continue
          if [[ "$url" =~ ^https://github\.com/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)/(issues|pull)/([0-9]+)$ ]]; then
            u_owner="${BASH_REMATCH[1]}"
            u_repo="${BASH_REMATCH[2]}"
            u_num="${BASH_REMATCH[4]}"
            if [[ -n "$ORIGIN_OWNER" && -n "$ORIGIN_REPO" \
                  && "$u_owner" == "$ORIGIN_OWNER" && "$u_repo" == "$ORIGIN_REPO" ]]; then
              printf '#%s\n' "$u_num"
            else
              printf '%s\n' "$url"
            fi
          else
            printf '%s\n' "$url"
          fi
        done
    # Bare #N tokens. Require a leading non-alphanumeric boundary so markdown
    # ATX headings (`# Title`) and inline hex-like tokens are filtered.
    printf '%s\n' "$CONTENT" \
      | grep_or_empty '(^|[[:space:][:punct:]])#[0-9]+' \
      | grep_or_empty '#[0-9]+'
  } | dedupe_stable
)

# --- JSON assembly ------------------------------------------------------------

arr_file_paths=$(printf '%s' "$file_paths" | emit_json_array)
arr_identifiers=$(printf '%s' "$identifiers" | emit_json_array)
arr_cross_refs=$(printf '%s' "$cross_refs" | emit_json_array)
arr_gh_refs=$(printf '%s' "$gh_refs" | emit_json_array)

if command -v jq >/dev/null 2>&1; then
  jq -cn \
    --argjson fp "$arr_file_paths" \
    --argjson id "$arr_identifiers" \
    --argjson cr "$arr_cross_refs" \
    --argjson gh "$arr_gh_refs" \
    '{filePaths: $fp, identifiers: $id, crossRefs: $cr, ghRefs: $gh}'
else
  printf '{"filePaths":%s,"identifiers":%s,"crossRefs":%s,"ghRefs":%s}\n' \
    "$arr_file_paths" "$arr_identifiers" "$arr_cross_refs" "$arr_gh_refs"
fi
