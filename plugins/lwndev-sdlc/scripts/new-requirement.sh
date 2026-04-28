#!/usr/bin/env bash
# new-requirement.sh — Allocate ID, slugify, and render a requirement document.
#
# Usage:
#   new-requirement.sh <FEAT|CHORE|BUG> <title> [--issue <ref>] \
#                      [--category <name>] [--severity <name>]
#
# Composes `next-id.sh` and `slugify.sh` (does NOT duplicate their logic) and
# writes the chosen template to:
#   requirements/features/FEAT-{NNN}-{slug}.md
#   requirements/chores/CHORE-{NNN}-{slug}.md
#   requirements/bugs/BUG-{NNN}-{slug}.md
#
# Substitutions are applied in-place against the existing template placeholders
# (no new mustache markers introduced):
#   `XXX`                                                  -> NNN
#   `[Brief Title]` / `[Feature Name]`                     -> <title>
#   `[#N](https://github.com/org/repo/issues/N)`           -> resolved issue link
#   category enum line (the bracketed `[a|b|c]` line)      -> picked category
#
# Flag rules (kept here, not in validate-categories.sh, to keep the CLI
# surface honest and to give the bats fixture deterministic rejection
# branches):
#   --severity is accepted only when <TYPE>=BUG.
#   --category is rejected when <TYPE>=FEAT (features have no category enum).
#   --category for CHORE/BUG is validated via validate-categories.sh.
#   --issue parses `git remote get-url origin` to derive <org>/<repo>;
#       SSH form  : git@github.com:<org>/<repo>(.git)?
#       HTTPS form: https://github.com/<org>/<repo>(.git)?
#       fallback  : if no remote / no match -> bare `#N` ref (no URL).
#
# Stdout: written path on a single line followed by a trailing newline.
#
# Exit codes:
#   0 success
#   1 filesystem/template error
#   2 usage/validation error
#
# Re-runs allocate a fresh ID monotonically; never overwrites a prior file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NEXT_ID="${SCRIPT_DIR}/next-id.sh"
SLUGIFY="${SCRIPT_DIR}/slugify.sh"
VALIDATE_CATEGORIES="${SCRIPT_DIR}/validate-categories.sh"

usage() {
  echo "error: usage: new-requirement.sh <FEAT|CHORE|BUG> <title> [--issue <ref>] [--category <name>] [--severity <name>]" >&2
}

if [ "$#" -lt 2 ]; then
  usage
  exit 2
fi

type_arg="$1"
title="$2"
shift 2

case "$type_arg" in
  FEAT|CHORE|BUG) ;;
  *)
    echo "error: invalid type '$type_arg' (expected FEAT, CHORE, or BUG)" >&2
    exit 2
    ;;
esac

if [ -z "$title" ]; then
  echo "error: title is empty" >&2
  exit 2
fi

issue=""
category=""
severity=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --issue)
      if [ "$#" -lt 2 ]; then
        echo "error: --issue requires a value" >&2
        exit 2
      fi
      issue="$2"
      shift 2
      ;;
    --category)
      if [ "$#" -lt 2 ]; then
        echo "error: --category requires a value" >&2
        exit 2
      fi
      category="$2"
      shift 2
      ;;
    --severity)
      if [ "$#" -lt 2 ]; then
        echo "error: --severity requires a value" >&2
        exit 2
      fi
      severity="$2"
      shift 2
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# --- Flag-vs-type rules ---

if [ -n "$severity" ] && [ "$type_arg" != "BUG" ]; then
  echo "error: --severity only accepted for BUG" >&2
  exit 2
fi

if [ -n "$category" ] && [ "$type_arg" = "FEAT" ]; then
  echo "error: --category not accepted for FEAT (features have no category enum)" >&2
  exit 2
fi

# Validate category for CHORE/BUG via the shared validator (pass-through stderr).
if [ -n "$category" ] && [ "$type_arg" != "FEAT" ]; then
  if ! bash "$VALIDATE_CATEGORIES" "$type_arg" "$category"; then
    exit 2
  fi
fi

# --- Resolve dir, template, and Plugin-Root template path ---

case "$type_arg" in
  FEAT)
    dir="requirements/features"
    template="${PLUGIN_ROOT}/skills/documenting-features/assets/feature-requirements.md"
    ;;
  CHORE)
    dir="requirements/chores"
    template="${PLUGIN_ROOT}/skills/documenting-chores/assets/chore-document.md"
    ;;
  BUG)
    dir="requirements/bugs"
    template="${PLUGIN_ROOT}/skills/documenting-bugs/assets/bug-document.md"
    ;;
esac

if [ ! -f "$template" ]; then
  echo "error: template not found: $template" >&2
  exit 1
fi

# --- Allocate ID and slug via the existing helpers ---

if ! id=$(bash "$NEXT_ID" "$type_arg"); then
  echo "error: next-id.sh failed for $type_arg" >&2
  exit 1
fi

if ! slug=$(bash "$SLUGIFY" "$title"); then
  # slugify.sh prints its own error to stderr; propagate exit code class.
  exit 2
fi

# --- Resolve issue link (only when --issue provided) ---

issue_link=""
if [ -n "$issue" ]; then
  # Strip a leading '#' if the caller passed `#42`.
  issue_num="${issue#\#}"
  org_repo=""
  if remote_url=$(git remote get-url origin 2>/dev/null); then
    # Strip optional trailing ".git" once, then match either SSH or HTTPS
    # form. Bash ERE has no non-greedy quantifier; pre-stripping is the
    # portable approach.
    stripped="${remote_url%.git}"
    if [[ "$stripped" =~ ^git@github\.com:([^/]+)/([^/]+)$ ]]; then
      org_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    elif [[ "$stripped" =~ ^https://github\.com/([^/]+)/([^/]+)$ ]]; then
      org_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    fi
  fi
  if [ -n "$org_repo" ]; then
    issue_link="[#${issue_num}](https://github.com/${org_repo}/issues/${issue_num})"
  else
    issue_link="#${issue_num}"
  fi
fi

# --- Compose output path; ensure dir exists; ensure no overwrite ---

mkdir -p "$dir"

out_path="${dir}/${type_arg}-${id}-${slug}.md"

if [ -e "$out_path" ]; then
  echo "error: refusing to overwrite existing file: $out_path" >&2
  exit 1
fi

# --- Read template, apply substitutions, write file ---

# Use python3 for safe in-place string substitution to avoid sed escaping
# pitfalls (titles/issues may contain `/`, `&`, etc.). python3 is part of
# the macOS/Linux base image used by this repo's tooling.
if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required for template rendering" >&2
  exit 1
fi

# Write atomically: render to a temp sibling, then rename.
tmp_path="${out_path}.tmp.$$"

if ! TYPE_ARG="$type_arg" \
     ID="$id" \
     TITLE="$title" \
     ISSUE_LINK="$issue_link" \
     CATEGORY="$category" \
     SEVERITY="$severity" \
     TEMPLATE_PATH="$template" \
     OUT_PATH="$tmp_path" \
     python3 - <<'PY'
import os
import re
import sys

t = os.environ["TYPE_ARG"]
nid = os.environ["ID"]
title = os.environ["TITLE"]
issue_link = os.environ["ISSUE_LINK"]
category = os.environ["CATEGORY"]
severity = os.environ["SEVERITY"]
template_path = os.environ["TEMPLATE_PATH"]
out_path = os.environ["OUT_PATH"]

try:
    with open(template_path, "r", encoding="utf-8") as fh:
        src = fh.read()
except OSError as exc:
    sys.stderr.write(f"error: failed to read template: {template_path} ({exc})\n")
    sys.exit(1)

# 1) `{TYPE}-XXX` -> `{TYPE}-{NNN}` (handle just the XXX suffix).
src = src.replace(f"{t}-XXX", f"{t}-{nid}")

# 2) Title placeholder. Templates use either "[Brief Title]" (chore/bug)
#    or "[Feature Name]" (feature). Replace the first occurrence so we
#    don't disturb similar-shaped placeholder text downstream.
for needle in ("[Brief Title]", "[Feature Name]"):
    if needle in src:
        src = src.replace(needle, title, 1)

# 3) GitHub Issue placeholder line.
#    Template line: `[#N](https://github.com/org/repo/issues/N)`
issue_placeholder = "[#N](https://github.com/org/repo/issues/N)"
if issue_link:
    src = src.replace(issue_placeholder, issue_link, 1)
# else: leave placeholder in template state (per AC).

# 4) Category enum line. Templates contain a bracketed pipe-delimited
#    enum on its own line, e.g. `[dependencies|documentation|refactoring|configuration|cleanup]`
#    or `[runtime-error|logic-error|ui-defect|performance|security|regression]`.
if category:
    src = re.sub(
        r"`\[[a-z][a-z0-9\-]*(?:\|[a-z][a-z0-9\-]*)+\]`",
        f"`{category}`",
        src,
        count=1,
    )

# 5) Severity enum line (BUG only). Same pattern, applied only when
#    --severity is provided.
if severity:
    src = re.sub(
        r"`\[critical\|high\|medium\|low\]`",
        f"`{severity}`",
        src,
        count=1,
    )

try:
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(src)
except OSError as exc:
    sys.stderr.write(f"error: failed to write rendered document: {out_path} ({exc})\n")
    sys.exit(1)
PY
then
  rm -f "$tmp_path"
  exit 1
fi

mv "$tmp_path" "$out_path"

# --- Echo path on stdout (with trailing newline, matches next-id.sh) ---

printf '%s\n' "$out_path"
