# Reviewing-Requirements Findings Handling

All `reviewing-requirements` fork steps (feature step 2; chore step 2; bug step 2) require findings handling after the subagent returns. The orchestrator parses the subagent's return text and acts on the findings before advancing.

## Parsing Findings

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/parse-findings.sh" <subagent-output-file>` — emits `{counts:{errors,warnings,info}, individual:[{id,severity,category,description}]}` on stdout. Zero counts when no summary line found.

## Decision Flow

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/findings-decision.sh" <ID> <stepIndex> '<counts-json>'` — emits `{action, reason, type, complexity}`. Dispatch on `action`:

| `action` | Orchestrator behavior |
|----------|----------------------|
| `advance` | call `advance` + continue |
| `auto-advance` | emit `[info]` log + call `advance` + continue |
| `prompt-user` | set gate + display findings + prompt user |
| `pause-errors` | set gate + display findings + offer apply-fixes / pause |

State-transition calls per branch:

- `advance` → `record-findings {ID} {stepIndex} 0 0 0 advanced 'No issues found'` then `advance {ID} "{artifact-path}"`.
- `auto-advance` → display findings; emit `[info] {N} warnings, {N} info from reviewing-requirements ({mode}) — auto-advancing (chain={type}, complexity={complexity})`; parse individual findings via `parse-findings.sh`'s `individual` field to `/tmp/findings-{ID}-{stepIndex}.json`; `record-findings {ID} {stepIndex} 0 {W} {I} auto-advanced '{summary}' --details-file /tmp/findings-{ID}-{stepIndex}.json` then `rm -f` that file; `advance {ID} "{artifact-path}"`.
- `prompt-user` → `set-gate {ID} findings-decision`; display findings; prompt "{N} warnings and {N} info found by reviewing-requirements. Review findings above and continue? (yes / no)"; `clear-gate {ID}`; if yes → `record-findings ... user-advanced` + `advance`; if no → `record-findings ... paused` + `pause {ID} review-findings` and halt.
- `pause-errors` → `set-gate {ID} findings-decision`; display findings + auto-fixable items from Fix Summary / Update Summary; offer Apply-fixes (→ `record-findings ... auto-fixed` then apply edits in main context then re-fork once, see Applying Auto-Fixes) or Pause (→ `record-findings ... paused` + `pause {ID} review-findings` and halt).

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

Use `parse-findings.sh`'s `individual` field (see `## Parsing Findings` above) — write the array to `/tmp/findings-{ID}-{stepIndex}.json`, pass `--details-file` to `record-findings`, remove the temp file after. Script emits `[warn] parse-findings: counts non-zero but no individual findings parsed — recording counts only.` to stderr when warnings/info are present but no individual lines match.
