# Reviewing-Requirements Findings Handling

All `reviewing-requirements` fork steps (feature step 2; chore step 2; bug step 2) require findings handling after the subagent returns. The orchestrator parses the subagent's return text and acts on the findings before advancing.

## Parsing Findings

After the `reviewing-requirements` subagent returns its summary, parse the summary line for severity counts:

```
Found **N errors**, **N warnings**, **N info**
```

Extract the error, warning, and info counts from this line. If the summary line is not found (e.g., the subagent returned "No issues found"), treat as zero errors, zero warnings, zero info.

> **Note**: Anchor the count-extraction regex on the `Found **N errors**` substring rather than the start of the line. Subagent output in test-plan mode may include a mode prefix (e.g., `"Test-plan reconciliation for {ID}: Found **N errors**..."`) before the counts — anchoring on the substring handles these prefixes correctly.

## Decision Flow

Based on the parsed counts, follow this flow:

1. **Zero findings** (zero errors, zero warnings, zero info) → Persist findings, then advance state automatically. No user interaction needed.
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-findings {ID} {stepIndex} 0 0 0 advanced 'No issues found'
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "{artifact-path}"
   ```

2. **Warnings/info only (zero errors)** → Read chain type and complexity from the state file:
   ```bash
   type=$(jq -r '.type' ".sdlc/workflows/{ID}.json")
   complexity=$(jq -r '.complexity // "medium"' ".sdlc/workflows/{ID}.json")
   ```
   Apply the gate:
   - **Bug or chore chain with `complexity == low` or `complexity == medium`** → Log the findings and auto-advance. Parse individual findings from the subagent return text using the FR-7 procedure described in the "Parsing Individual Findings for `auto-advanced` Decisions" subsection below, write them to a temp file, then persist and advance:
     ```
     [info] {N} warnings, {N} info from reviewing-requirements ({mode}) — auto-advancing (chain={type}, complexity={complexity})
     ```
     Display the full findings to the user (for visibility), emit the `[info]` line above, then:
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-findings {ID} {stepIndex} 0 {W} {I} auto-advanced '{summary}' --details-file /tmp/findings-{ID}-{stepIndex}.json
     rm -f /tmp/findings-{ID}-{stepIndex}.json
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "{artifact-path}"
     ```
     Do not prompt.
   - **Bug or chore chain with `complexity == high`**, or **any feature chain** → Display the full findings to the user. Set the gate before prompting so the stop hook does not nudge while waiting for input:
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-gate {ID} findings-decision
     ```
     Prompt: "{N} warnings and {N} info found by reviewing-requirements. Review findings above and continue? (yes / no)". After the user responds, clear the gate:
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh clear-gate {ID}
     ```
     If the user confirms, persist findings then advance state:
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-findings {ID} {stepIndex} 0 {W} {I} user-advanced '{summary}'
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "{artifact-path}"
     ```
     If the user declines, persist findings then pause the workflow:
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-findings {ID} {stepIndex} 0 {W} {I} paused '{summary}'
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} review-findings
     ```
     Halt execution. The user re-invokes with `/orchestrating-workflows {ID}` after addressing findings manually.

3. **Errors present** → Display the full findings to the user. List the auto-fixable items from the "Fix Summary" / "Update Summary" section of the findings. Errors always block progression — set the gate before presenting options so the stop hook does not nudge while waiting for input:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-gate {ID} findings-decision
   ```
   Present two options:
   - **Apply fixes** → Persist findings at the decision point, then keep the gate active during fix application and re-verification (the gate suppresses stop-hook nudges for the entire fix+re-run cycle):
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-findings {ID} {stepIndex} {E} {W} {I} auto-fixed '{summary}'
     ```
     Apply the auto-fixable corrections in main context using the Edit tool. Then spawn a **new** `reviewing-requirements` subagent fork to re-verify (this is the re-run, max 1). The gate is cleared after the re-run completes and the outcome is determined — see "Applying Auto-Fixes" below.
   - **Pause for manual resolution** → Persist findings then pause immediately (the `pause` command clears the gate automatically):
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-findings {ID} {stepIndex} {E} {W} {I} paused '{summary}'
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} review-findings
     ```
     Halt execution.

## Applying Auto-Fixes

When the user opts to apply fixes, the orchestrator (not a subagent) applies them. The gate remains active throughout this entire sequence to suppress stop-hook nudges:

1. Read the auto-fixable items from the findings (listed under "Auto-fixable" or "Applicable updates" in the subagent's return text)
2. For each fix, use the Edit tool to apply the correction to the target file
3. After all fixes are applied, spawn a new `reviewing-requirements` subagent fork with the same arguments as the original step to re-verify
4. This re-run is the single allowed retry. After the re-run completes, clear the gate and act on the outcome — **do not apply any further edits regardless of what the re-run findings contain**:
   - If the re-run returns zero errors → persist re-run findings, then clear the gate, then advance state. Normalize `{rerun-summary}` to `'No issues found'` when the re-run returns zero counts (see summary normalization note in "Persisting Findings" below).
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-findings {ID} {stepIndex} 0 0 0 advanced 'No issues found' --rerun
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh clear-gate {ID}
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "{artifact-path}"
     ```
   - If the re-run returns warnings/info only (zero errors) → parse individual findings using the FR-7 procedure, then persist re-run findings, then clear the gate, then advance state unconditionally. Zero errors after a fix pass means the fixes succeeded; residual warnings are accepted.
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-findings {ID} {stepIndex} 0 {W2} {I2} auto-advanced '{rerun-summary}' --rerun --details-file /tmp/findings-{ID}-{stepIndex}.json
     rm -f /tmp/findings-{ID}-{stepIndex}.json
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh clear-gate {ID}
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "{artifact-path}"
     ```
   - If the re-run returns errors → display the remaining findings, then persist re-run findings, then pause with `review-findings` (the `pause` command clears the gate automatically). Do not attempt to fix the errors.
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-findings {ID} {stepIndex} {E2} {W2} {I2} paused '{rerun-summary}' --rerun
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} review-findings
     ```
     Halt execution.

## Persisting Findings

At every reviewing-requirements decision point, call `record-findings` **before** `advance` or `pause` to persist the findings in the workflow state file. The call must always precede the state-transition call so that findings survive even if the transition call fails or the process exits.

### Decision-to-Call Mapping

| Decision taken | `record-findings` invocation |
|---|---|
| Zero findings → auto-advance | `record-findings {ID} {stepIndex} 0 0 0 advanced 'No issues found'` |
| Warnings/info only → auto-advance (FEAT-015 gate) | `record-findings {ID} {stepIndex} 0 {W} {I} auto-advanced '{summary}' --details-file {tmp}` |
| Warnings/info only → user confirmed | `record-findings {ID} {stepIndex} 0 {W} {I} user-advanced '{summary}'` |
| Warnings/info only → user declined | `record-findings {ID} {stepIndex} 0 {W} {I} paused '{summary}'` |
| Errors present → user chose "Apply fixes" | `record-findings {ID} {stepIndex} {E} {W} {I} auto-fixed '{summary}'` |
| Errors present → user chose "Pause" | `record-findings {ID} {stepIndex} {E} {W} {I} paused '{summary}'` |
| Re-run after auto-fix (any outcome) | `record-findings {ID} {stepIndex} {E2} {W2} {I2} {rerun-decision} '{rerun-summary}' --rerun` |
| Re-run after auto-fix → auto-advanced | (same as above plus `--details-file {tmp}`) |

Notes:
- `{stepIndex}` is the zero-based index in the `steps` array for the current reviewing-requirements step. Use the chain-step-to-index table: feature step 2 maps to index 1; chore/bug step 2 maps to index 1.
- When the subagent returns `"No issues found"` or `Found **0 errors**, **0 warnings**, **0 info**`, normalize to `'No issues found'` as the canonical summary.
- The `{summary}` must be passed as a single shell-quoted token. Use single quotes around the summary string to handle embedded special characters.

### Parsing Individual Findings for `auto-advanced` Decisions

When `decision` is `auto-advanced`, parse individual findings from the subagent return text to build the `--details-file` argument:

1. Scan the subagent return text for lines matching: `**[{W|I}{N}] {category} — {description}**` (or the unbolded variant). The separator is an em dash (`—`, U+2014); accept ASCII double-hyphen (`--`) as a fallback. Map prefix letters: `W` → `"warning"`, `I` → `"info"`.
2. For each match, extract:
   - `id` — severity+number token (e.g., `"W1"`, `"I3"`)
   - `severity` — mapped from prefix letter
   - `category` — text between `]` and `—`, trimmed
   - `description` — text after `—` to end of line, trimmed and stripped of trailing bold markers
3. Write the resulting JSON array to `/tmp/findings-{ID}-{stepIndex}.json`
4. Pass `--details-file /tmp/findings-{ID}-{stepIndex}.json` to `record-findings`
5. Remove the temp file after `record-findings` returns

If no individual findings can be parsed despite non-zero counts, write `[]` and log: `[warn] Could not parse individual findings from reviewing-requirements output — recording counts only.`
