#!/usr/bin/env bash
# check-idempotent.sh — Three-condition BK-3 idempotency check (FR-4).
#
# Usage: check-idempotent.sh <doc-path> <prNumber>
#
# Exits 0 (silent) when all three conditions hold:
#   1. `## Acceptance Criteria` section is absent OR has zero unticked
#      `- [ ]` lines outside fenced code blocks.
#   2. `## Completion` section exists with a line matching
#      `**Status:** \`Complete\`` OR `**Status:** \`Completed\``
#      (inside the completion section body, outside fenced blocks).
#   3. A `**Pull Request:**` line within the `## Completion` section body
#      contains `[#<prNumber>]` OR `/pull/<prNumber>` for the exact number
#      passed as the second arg.
#
# On failure, emits exactly one line to stderr:
#   `[info] idempotent check failed: <label>`
# where <label> is one of:
#   acceptance-criteria-unticked
#   completion-section-missing
#   pr-line-mismatch
# First-failing condition wins. No stdout on failure.
#
# Scanning rules (inherited from checkbox-flip-all.sh):
#   - `## <heading>` lines inside fenced code blocks are NOT section starts.
#   - Fences open/close on lines whose first non-whitespace run is
#     ``` or ~~~.
#   - Line endings are preserved on read (CRLF detected; scan uses
#     CR-stripped copies, but file content is not rewritten).
#
# Exit codes:
#   0 all three conditions hold (silent)
#   1 any condition fails ([info] stderr line, no stdout)
#   2 missing/invalid args OR non-existent doc path

set -euo pipefail

usage() {
  echo "[error] check-idempotent: usage: check-idempotent.sh <doc-path> <prNumber>" >&2
  exit 2
}

if [ "$#" -ne 2 ]; then
  usage
fi

doc="$1"
pr_number_arg="$2"

# Validate prNumber as a positive integer (no leading '#', no sign).
if ! [[ "$pr_number_arg" =~ ^[0-9]+$ ]] || [ "$pr_number_arg" -le 0 ]; then
  usage
fi

if [ ! -f "$doc" ]; then
  echo "[error] check-idempotent: file not found: ${doc}" >&2
  exit 2
fi

# Scan in a single awk pass. Track fenced-block state. For each line:
#   - Detect `## Acceptance Criteria` and `## Completion` real sections.
#   - Within Acceptance Criteria body (outside fences), count `- [ ]` lines.
#   - Within Completion body (outside fences), detect Status and PR lines.
#
# We emit three tokens to stdout (then discard): `AC_UNTICKED=N`,
# `COMPLETION_FOUND=0|1`, `PR_MATCH=0|1`, plus diagnostic data for the
# "first failing condition" tie-break.
results="$(awk -v prn="$pr_number_arg" '
  BEGIN {
    in_fence = 0
    in_ac = 0
    in_completion = 0
    ac_unticked = 0
    completion_found = 0
    status_found_in_completion = 0
    pr_match = 0
  }
  {
    # Strip CR for matching; original line content is discarded — we emit
    # counters, not modified content.
    line = $0
    sub(/\r$/, "", line)

    # Fence toggling: first non-whitespace run of ``` or ~~~.
    stripped = line
    sub(/^[ \t]+/, "", stripped)
    if (stripped ~ /^(```|~~~)/) {
      in_fence = !in_fence
      next
    }

    if (in_fence) { next }

    # Section boundaries: an H2 heading outside any fence closes any
    # currently-open real section.
    if (substr(line, 1, 3) == "## ") {
      in_ac = 0
      in_completion = 0
      if (line == "## Acceptance Criteria") {
        in_ac = 1
        next
      }
      if (line == "## Completion") {
        in_completion = 1
        completion_found = 1
        next
      }
      next
    }

    if (in_ac) {
      # Count unticked `- [ ] ` (or line-starting variants with leading
      # whitespace). Mirror checkbox-flip-all.sh regex: `-[ ]\[[ ]\][ ]`.
      s = line
      sub(/^[ \t]+/, "", s)
      if (s ~ /^-[ ]\[[ ]\][ ]/) {
        ac_unticked++
      }
    }

    if (in_completion) {
      # Status detection: `**Status:** ` followed by backticked Complete/Completed.
      # Accept both `Complete` and `Completed`.
      if (line ~ /\*\*Status:\*\*[ \t]+`Complete`/ || line ~ /\*\*Status:\*\*[ \t]+`Completed`/) {
        status_found_in_completion = 1
      }
      # PR line detection: `**Pull Request:**` containing [#N] or /pull/N.
      if (line ~ /\*\*Pull Request:\*\*/) {
        # Need [#<prn>] or /pull/<prn> with exact match (not substring of a
        # larger number). Use word boundaries via surrounding non-digit chars.
        pattern1 = "\\[#" prn "\\]"
        pattern2 = "/pull/" prn "([^0-9]|$)"
        if (line ~ pattern1) pr_match = 1
        else if (line ~ pattern2) pr_match = 1
      }
    }
  }
  END {
    printf "AC_UNTICKED=%d\n", ac_unticked
    printf "COMPLETION_FOUND=%d\n", completion_found
    printf "STATUS_IN_COMPLETION=%d\n", status_found_in_completion
    printf "PR_MATCH=%d\n", pr_match
  }
' "$doc")"

ac_unticked="$(printf '%s\n' "$results" | sed -n 's/^AC_UNTICKED=//p')"
completion_found="$(printf '%s\n' "$results" | sed -n 's/^COMPLETION_FOUND=//p')"
status_in_completion="$(printf '%s\n' "$results" | sed -n 's/^STATUS_IN_COMPLETION=//p')"
pr_match="$(printf '%s\n' "$results" | sed -n 's/^PR_MATCH=//p')"

# First-failing condition wins: AC → Completion → PR line.
if [ "${ac_unticked:-0}" -gt 0 ]; then
  echo "[info] idempotent check failed: acceptance-criteria-unticked" >&2
  exit 1
fi

# Condition 2: Completion section must exist AND contain the Complete(d) status.
if [ "${completion_found:-0}" -ne 1 ] || [ "${status_in_completion:-0}" -ne 1 ]; then
  echo "[info] idempotent check failed: completion-section-missing" >&2
  exit 1
fi

if [ "${pr_match:-0}" -ne 1 ]; then
  echo "[info] idempotent check failed: pr-line-mismatch" >&2
  exit 1
fi

exit 0
