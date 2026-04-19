#!/usr/bin/env bash
set -euo pipefail

# stop-hook.sh — Validate the version-2 QA plan artifact.
#
# Reads Claude Code stop-hook JSON from stdin; checks that the
# documenting-qa skill has produced a well-formed version-2 plan
# artifact at qa/test-plans/QA-plan-{ID}.md. Grades on artifact
# structure (FEAT-018) rather than regex-matching the last assistant
# message, which was the root cause of the false-PASS failure mode
# in BUG-010 / issue #163.
#
# Exit codes:
#   0 — allow stop (artifact is valid; or skill not active; or stop_hook_active set)
#   2 — block stop (artifact missing or malformed; actionable error on stderr)
#
# Validation rules (FR-4 / FR-9):
#   1. Frontmatter present (leading `---` block).
#   2. Frontmatter contains `version: 2`.
#   3. `## User Summary` section present.
#   4. `## Capability Report` section present.
#   5. `## Scenarios (by dimension)` section present with at least one of
#      the five dimension subsections (### Inputs / State transitions /
#      Environment / Dependency failure / Cross-cutting) OR at least one
#      corresponding entry in `## Non-applicable dimensions`.
#   6. Every scenario line under a dimension subsection matches the shape
#      `- [P0|P1|P2] ... | mode: <test-framework|exploratory> | ...`.
#   7. The `## Scenarios (by dimension)` section contains NO `FR-\d+`
#      references (FR-4 no-spec rule). References in other sections
#      such as `## Reconciliation Delta` are permitted.
#
# Exit-code 2 messages are specific; they are surfaced back to the agent
# and are meant to be actionable (tell the agent exactly what to fix).

ACTIVE_FILE=".sdlc/qa/.documenting-active"
QA_PLAN_DIR="qa/test-plans"

# ---------------------------------------------------------------------------
# Guards — cheap exits before we parse any input.
# ---------------------------------------------------------------------------

# Skill not active: allow stop.
if [[ ! -f "$ACTIVE_FILE" ]]; then
  exit 0
fi

# Read stdin JSON; if empty or unreadable, allow stop to avoid trapping.
INPUT="$(cat)" || exit 0
if [[ -z "$INPUT" ]]; then
  exit 0
fi

# stop_hook_active bypass — the loop escape hatch; always honored.
STOP_HOOK_ACTIVE="$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  rm -f "$ACTIVE_FILE"
  exit 0
fi

# Extract the last assistant message for ID detection.
MESSAGE="$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || echo "")"

# ---------------------------------------------------------------------------
# Locate the plan artifact.
# ---------------------------------------------------------------------------
# Strategy: first try to extract a QA-plan-{ID}.md reference from the
# message. If none is present, fall back to the single file in
# qa/test-plans/ (if exactly one exists). Otherwise block.

PLAN_PATH=""

if [[ -n "$MESSAGE" ]]; then
  # Match QA-plan-<ID>.md where ID may contain uppercase letters/digits/dashes.
  # grep -oE extracts just the matched token.
  CAND="$(echo "$MESSAGE" | grep -oE 'QA-plan-[A-Za-z0-9_-]+\.md' | head -n 1 || true)"
  if [[ -n "$CAND" ]]; then
    PLAN_PATH="${QA_PLAN_DIR}/${CAND}"
  fi
fi

if [[ -z "$PLAN_PATH" ]]; then
  # Fall back: if exactly one v2 plan exists in the directory, use it.
  if [[ -d "$QA_PLAN_DIR" ]]; then
    MATCHES=()
    while IFS= read -r -d '' f; do
      MATCHES+=("$f")
    done < <(find "$QA_PLAN_DIR" -maxdepth 1 -type f -name 'QA-plan-*.md' -print0 2>/dev/null)
    if [[ ${#MATCHES[@]} -eq 1 ]]; then
      PLAN_PATH="${MATCHES[0]}"
    fi
  fi
fi

if [[ -z "$PLAN_PATH" ]]; then
  echo "Stop hook: could not determine QA plan artifact path from the last assistant message. Reference the file path in your final message (e.g., 'Plan saved to qa/test-plans/QA-plan-FEAT-001.md')." >&2
  exit 2
fi

if [[ ! -f "$PLAN_PATH" ]]; then
  echo "Stop hook: plan artifact ${PLAN_PATH} does not exist. The documenting-qa skill must write the plan before stopping." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Structural validation.
# ---------------------------------------------------------------------------

# 1. Frontmatter present.
FIRST_LINE="$(head -n 1 "$PLAN_PATH" 2>/dev/null || true)"
# Skip HTML comments at the top of the file (documentation preamble).
if [[ "$FIRST_LINE" == "<!--" ]]; then
  # Find the first line after the closing --> that equals exactly "---".
  FM_START="$(awk '
    /^<!--/ { in_c = 1 }
    in_c && /-->/ { in_c = 0; next }
    !in_c && $0 == "---" { print NR; exit }
  ' "$PLAN_PATH")"
else
  FM_START="$(awk '$0 == "---" { print NR; exit }' "$PLAN_PATH")"
fi

if [[ -z "${FM_START:-}" ]]; then
  echo "Stop hook: plan artifact ${PLAN_PATH} is missing YAML frontmatter (expected leading '---' block with id, version, timestamp, persona)." >&2
  exit 2
fi

# Extract frontmatter block (between the first two `---` lines).
FRONTMATTER="$(awk -v start="$FM_START" '
  NR == start { in_fm = 1; next }
  in_fm && $0 == "---" { closed = 1; exit }
  in_fm
  END { if (!closed) exit 1 }
' "$PLAN_PATH")" || FRONTMATTER=""

# Re-check closure explicitly: count `---` lines from FM_START onward and
# ensure at least two were seen (opening + closing).
FM_DELIMS="$(awk -v start="$FM_START" '
  NR >= start && $0 == "---" { n++ }
  END { print n+0 }
' "$PLAN_PATH")"

if [[ -z "$FRONTMATTER" || "$FM_DELIMS" -lt 2 ]]; then
  echo "Stop hook: plan artifact ${PLAN_PATH} has empty or unclosed frontmatter block (missing closing '---')." >&2
  exit 2
fi

# 2. version: 2 in frontmatter.
if ! echo "$FRONTMATTER" | grep -qE '^[[:space:]]*version[[:space:]]*:[[:space:]]*2[[:space:]]*$'; then
  echo "Stop hook: plan artifact ${PLAN_PATH} is missing 'version: 2' in frontmatter. Version 1 artifacts have no version field; new artifacts from the FEAT-018 redesign must declare 'version: 2'." >&2
  exit 2
fi

# 3. Required sections present.
require_section() {
  local heading="$1"
  if ! grep -qE "^${heading}[[:space:]]*\$" "$PLAN_PATH"; then
    echo "Stop hook: plan artifact ${PLAN_PATH} is missing required section '${heading}'." >&2
    exit 2
  fi
}

require_section '## User Summary'
require_section '## Capability Report'
# Scenarios heading is matched loosely because the "(by dimension)" suffix
# may be slightly reformatted. Require it to start with "## Scenarios".
if ! grep -qE '^## Scenarios' "$PLAN_PATH"; then
  echo "Stop hook: plan artifact ${PLAN_PATH} is missing '## Scenarios (by dimension)' section." >&2
  exit 2
fi

# 4. Scope the Scenarios section for dimension coverage and FR-N checks.
# Use sed to extract from the Scenarios heading to the next `## ` heading.
SCENARIOS_BLOCK="$(sed -n '/^## Scenarios/,/^## /p' "$PLAN_PATH" | sed '$d')"
# If the last `## ` section was Scenarios itself (no following top-level
# heading), sed above strips the final line; re-read if block is empty.
if [[ -z "$SCENARIOS_BLOCK" ]]; then
  SCENARIOS_BLOCK="$(sed -n '/^## Scenarios/,$p' "$PLAN_PATH")"
fi

# 5. No-spec rule (FR-4): Scenarios section MUST NOT contain FR-\d+.
if echo "$SCENARIOS_BLOCK" | grep -qE 'FR-[0-9]+'; then
  echo "Stop hook: plan artifact ${PLAN_PATH} contains 'FR-N' references inside the '## Scenarios (by dimension)' section. FR-4 forbids copying requirement rows into the plan — the planning agent must not read the requirements doc during plan construction." >&2
  exit 2
fi

# 6. Dimension coverage: at least one of the five dimension subsections
#    OR at least one entry under `## Non-applicable dimensions`.
HAS_DIMENSION=false
for dim in '### Inputs' '### State transitions' '### Environment' '### Dependency failure' '### Cross-cutting'; do
  if echo "$SCENARIOS_BLOCK" | grep -qE "^${dim}"; then
    HAS_DIMENSION=true
    break
  fi
done

HAS_NONAPPLICABLE_ENTRY=false
if grep -qE '^## Non-applicable dimensions[[:space:]]*$' "$PLAN_PATH"; then
  NA_BLOCK="$(sed -n '/^## Non-applicable dimensions/,/^## /p' "$PLAN_PATH")"
  # At least one list item starting with `- ` that is not a blank list marker.
  if echo "$NA_BLOCK" | grep -qE '^- [^[:space:]]'; then
    HAS_NONAPPLICABLE_ENTRY=true
  fi
fi

if [[ "$HAS_DIMENSION" != "true" && "$HAS_NONAPPLICABLE_ENTRY" != "true" ]]; then
  echo "Stop hook: plan artifact ${PLAN_PATH} covers zero dimensions and has no entries in '## Non-applicable dimensions'. Every applicable adversarial dimension must either have at least one scenario or an explicit non-applicable justification (FR-6 / FR-8)." >&2
  exit 2
fi

# 7. Each scenario line under a dimension subsection must have priority +
#    execution mode. Scan every line starting with `- [` inside the
#    Scenarios block. Lines inside Non-applicable dimensions are handled
#    above and not validated here.
BAD_LINE=""
while IFS= read -r line; do
  # Only list items starting with `- [` are validated.
  if [[ "$line" =~ ^-[[:space:]]*\[ ]]; then
    # Must match `- [P0|P1|P2] ... | mode: test-framework|exploratory ...`
    if ! echo "$line" | grep -qE '^-[[:space:]]*\[P[0-2]\][[:space:]]'; then
      BAD_LINE="$line"
      break
    fi
    if ! echo "$line" | grep -qE 'mode:[[:space:]]*(test-framework|exploratory)'; then
      BAD_LINE="$line"
      break
    fi
  fi
done <<< "$SCENARIOS_BLOCK"

if [[ -n "$BAD_LINE" ]]; then
  echo "Stop hook: plan artifact ${PLAN_PATH} contains a scenario line missing a priority tag ([P0|P1|P2]) or execution mode (mode: test-framework|exploratory). Offending line: ${BAD_LINE}" >&2
  exit 2
fi

# All checks passed.
rm -f "$ACTIVE_FILE"
exit 0
