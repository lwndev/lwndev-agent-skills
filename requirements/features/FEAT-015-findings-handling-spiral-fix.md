# Feature Requirements: Fix Findings-Handling Spiral on Bug/Chore Chains

## Overview

Update the `orchestrating-workflows` skill's Reviewing-Requirements Findings Handling to auto-advance on warnings-only findings for bug/chore chains at `complexity <= medium`, and enforce the "single re-run, no follow-up edits" rule so that no edits occur after the re-run regardless of re-run findings.

## Feature ID
`FEAT-015`

## GitHub Issue
[#139](https://github.com/lwndev/lwndev-marketplace/issues/139)

## Priority
Medium - Eliminates a 3-6 minute edit spiral observed in real bug/chore workflows where polish warnings trigger unnecessary interactive prompts and cascading fix passes on routine work items.

## User Story

As a developer running bug or chore workflows via `orchestrating-workflows`, I want the orchestrator to auto-advance past warnings-only findings when my work item is low or medium complexity, and to never apply additional edits after a re-run, so that routine workflows complete without unnecessary interactive pauses or cascading fix spirals.

## Motivation

During BUG-009, the `reviewing-requirements` standard-mode fork returned 0 errors, 4 warnings, 2 info. Per the current Decision Flow (SKILL.md lines 268-272), the orchestrator prompted the user, who said "Address all 4 warnings". This triggered a 3+ minute edit spiral: 5 Edit calls, a re-run fork (1m 25s), then 3 more Edit calls after the re-run — all for polish findings, none for correctness. The re-run itself surfaced 1 new warning + 3 new info that were pure residue from the first fix pass, and the orchestrator continued editing instead of halting.

Two root causes:
1. The warnings-only prompt is applied uniformly regardless of chain type or complexity — routine bug/chore work doesn't benefit from the interactive loop.
2. The "single re-run" rule (SKILL.md line 295) says "do not apply fixes or re-run again after this" but is not strong enough to prevent the orchestrator from applying further edits when the re-run surfaces new findings.

## Functional Requirements

### FR-1: Auto-Advance on Warnings-Only for Bug/Chore Chains (T3)

Modify the Decision Flow's "Warnings/info only (zero errors)" branch to add a chain-type and complexity gate:

- **Bug/chore chains with `complexity <= medium`**: Log the findings as informational (display them to the user with an `[info]` prefix) and auto-advance state. Do not prompt the user for confirmation. Do not pause.
- **Bug/chore chains with `complexity == high`**: Retain the existing behavior — prompt the user for confirmation before advancing.
- **Feature chains (all complexities)**: Retain the existing behavior — prompt the user for confirmation before advancing.

The complexity value is read from the persisted state file (`jq -r '.complexity' ".sdlc/workflows/{ID}.json"`).

### FR-2: Chain-Type Awareness in Decision Flow

The Decision Flow must be able to determine the current chain type. Read the chain type from the persisted state file (`jq -r '.type' ".sdlc/workflows/{ID}.json"`). The type field is one of `feature`, `chore`, or `bug`, set at workflow init.

### FR-3: No Edits After Re-Run (T4)

Strengthen the "Applying Auto-Fixes" section's re-run enforcement rule (currently line 295) to make it unambiguous:

- After the re-run completes, the orchestrator must **not** apply any further edits, regardless of what the re-run findings contain.
- If the re-run returns zero errors: advance state.
- If the re-run returns errors: display the remaining findings and pause with `review-findings`. Do **not** attempt to fix the errors.
- If the re-run returns warnings/info only (zero errors): advance state unconditionally. The re-run path is always post-errors-present; zero errors after a fix pass means the fixes succeeded.
- This rule applies to all chain types and all complexities.

### FR-4: Informational Logging for Auto-Advanced Findings

When FR-1 triggers auto-advance, emit a console line in the format:

```
[info] {N} warnings, {N} info from reviewing-requirements ({mode}) — auto-advancing (chain={type}, complexity={complexity})
```

This gives the user visibility into what was skipped without blocking progression.

## Non-Functional Requirements

### NFR-1: No Feature-Chain Regression

Feature-chain behavior must be completely unchanged. All three `reviewing-requirements` modes (standard, test-plan, code-review) in feature chains continue to prompt the user on warnings/info-only findings regardless of complexity.

### NFR-2: Scope of Changes

Changes are limited to:
1. The `orchestrating-workflows` SKILL.md — specifically the "Decision Flow" and "Applying Auto-Fixes" subsections within the "Reviewing-Requirements Findings Handling" section.
2. No changes to the `reviewing-requirements` skill itself.
3. No changes to the `workflow-state.sh` script.
4. No changes to the state file schema.

### NFR-3: Deterministic Behavior

The auto-advance decision must be deterministic based on two inputs: chain type (from state file) and complexity (from state file). No heuristics or LLM judgment involved in the gate.

## Edge Cases

1. **Complexity is null**: If the state file's `complexity` field is `null` (workflow initialized but classifier not yet run, or pre-FEAT-014 migrated state), treat as `medium` for the purposes of FR-1. Use null-coalescing in the jq guard: `jq -r '.complexity // "medium"'`. This means bug/chore chains with null complexity would auto-advance on warnings-only — safe default since null complexity implies a simple work item that predates adaptive selection.
2. **Re-run produces new errors from fix residue**: FR-3 handles this — pause with `review-findings`, do not attempt further edits.
3. **Re-run produces new warnings from fix residue**: FR-3 handles this — advance state since there are zero errors. The warnings are accepted as residue.
4. **High-complexity chore/bug**: Retains the existing interactive prompt behavior, identical to feature chains.
5. **Mixed findings (errors + warnings) on initial run**: FR-1 does not apply — the "Errors present" branch is taken regardless of chain type or complexity. Only the "Warnings/info only" branch is gated.

## Testing Requirements

### Unit Tests
- Not applicable — changes are to SKILL.md prose, not executable code.

### Integration Tests
- Not applicable — the changes are behavioral instructions for the orchestrator.

### Manual Testing
- Run a bug or chore workflow at `complexity == low` or `medium` where `reviewing-requirements` returns warnings-only findings. Verify auto-advance without prompt.
- Run a bug or chore workflow at `complexity == high` where `reviewing-requirements` returns warnings-only findings. Verify the user is prompted.
- Run a feature workflow at any complexity where `reviewing-requirements` returns warnings-only findings. Verify the user is prompted.
- Run any workflow where the user opts to apply fixes, the re-run produces new warnings. Verify no further edits are applied and state advances.
- Run any workflow where the user opts to apply fixes, the re-run produces new errors. Verify no further edits are applied and the workflow pauses.

## Acceptance Criteria

- [ ] Bug/chore chains with `complexity <= medium` auto-advance on warnings-only findings from `reviewing-requirements` standard mode
- [ ] Bug/chore chains with `complexity <= medium` auto-advance on warnings-only findings from `reviewing-requirements` test-plan and code-review modes
- [ ] The "no edits after re-run" rule is unambiguous — the re-run is terminal regardless of findings
- [ ] Feature-chain behavior is unchanged at all complexities
- [ ] `complexity == high` bug/chore chains still prompt the user on warnings-only findings
- [ ] Auto-advanced findings are logged with the `[info]` format from FR-4
