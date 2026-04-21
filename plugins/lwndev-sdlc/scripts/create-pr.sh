#!/usr/bin/env bash
# create-pr.sh — Push the current branch and open a pull request (FR-9).
#
# Usage: create-pr.sh <type> <ID> <summary> [--closes <issueRef>]
#
# Behavior:
#   - Validates <type> is one of: feat, chore, fix.
#   - If --closes <issueRef> is provided, the <issueRef> must be non-empty
#     and not a bare `#` (usage error otherwise).
#   - Reads current branch via `git rev-parse --abbrev-ref HEAD`.
#   - Pushes with `git push -u origin <branch>`; on failure, exits 1 and
#     does NOT invoke gh.
#   - Assembles PR title `<type>(<ID>): <summary>`.
#   - Reads the PR body template from `${BASH_SOURCE%/*}/assets/pr-body.tmpl`.
#     Placeholders are bash-parameter-expansion-style `${VAR}` tokens:
#       ${TYPE} ${ID} ${SUMMARY} ${CLOSES_LINE} ${GENERATED_WITH}
#     Substitution is performed in bash (NOT envsubst) so no external
#     dependency is required and all characters (slashes, ampersands) are
#     handled safely. ${CLOSES_LINE} is either `Closes <issueRef>` or empty.
#     ${GENERATED_WITH} is the literal Claude Code trailer.
#   - Runs `gh pr create --title <title> --body <body>`.
#   - On success: prints the PR URL (gh's stdout) and exits 0.
#   - On failure: forwards gh stderr and exits 1.
#
# Exit codes:
#   0 success (PR URL printed to stdout)
#   1 git push or gh pr create failure
#   2 usage error (missing/invalid args, malformed --closes)

set -euo pipefail

# Bash 5.2+ enables patsub_replacement by default, which makes `&' in the
# replacement of `${var//pat/rep}` refer to the matched text. We rely on
# `&' staying literal when substituting user-supplied summaries that may
# contain ampersands; disable the shopt here (no-op on older bash).
shopt -u patsub_replacement 2>/dev/null || true

usage() {
  echo "error: usage: create-pr.sh <type> <ID> <summary> [--closes <issueRef>]" >&2
  exit 2
}

# Positional collection + optional --closes parsing.
positional=()
closes=""
closes_set=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --closes)
      if [ "$#" -lt 2 ]; then
        echo "error: --closes requires an argument" >&2
        exit 2
      fi
      closes="$2"
      closes_set=1
      shift 2
      ;;
    --closes=*)
      closes="${1#--closes=}"
      closes_set=1
      shift
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do positional+=("$1"); shift; done
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

if [ "${#positional[@]}" -ne 3 ]; then
  usage
fi

type="${positional[0]}"
id="${positional[1]}"
summary="${positional[2]}"

case "$type" in
  feat|chore|fix) ;;
  *)
    echo "error: invalid type '${type}' (expected feat, chore, or fix)" >&2
    exit 2
    ;;
esac

if [ "$closes_set" -eq 1 ]; then
  # Empty string or bare `#` are malformed.
  if [ -z "$closes" ] || [ "$closes" = "#" ]; then
    echo "error: --closes value is malformed" >&2
    exit 2
  fi
fi

# Determine current branch, then push.
branch=$(git rev-parse --abbrev-ref HEAD)

if ! git push -u origin "$branch"; then
  exit 1
fi

# Build title and body.
title="${type}(${id}): ${summary}"

tmpl_path="${BASH_SOURCE%/*}/assets/pr-body.tmpl"
if [ ! -f "$tmpl_path" ]; then
  echo "error: template not found: ${tmpl_path}" >&2
  exit 1
fi

tmpl_body=$(cat "$tmpl_path")

if [ "$closes_set" -eq 1 ]; then
  closes_line="Closes ${closes}"
else
  closes_line=""
fi

generated_with='🤖 Generated with [Claude Code](https://claude.com/claude-code)'

# Perform placeholder substitution via bash parameter expansion.
# The literal placeholder in the template is `${VAR}`; we replace it as a fixed
# string (no pattern interpretation). Bash 5.2+ adds `patsub_replacement` which
# would re-interpret `&' in the replacement as the matched text — we disable it
# at the top of this script so `&' stays literal in user-supplied summaries.
body="$tmpl_body"
body="${body//\$\{TYPE\}/$type}"
body="${body//\$\{ID\}/$id}"
body="${body//\$\{SUMMARY\}/$summary}"
body="${body//\$\{CLOSES_LINE\}/$closes_line}"
body="${body//\$\{GENERATED_WITH\}/$generated_with}"

if ! gh pr create --title "$title" --body "$body"; then
  exit 1
fi
