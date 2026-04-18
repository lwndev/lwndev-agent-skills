# Feature Requirements: Remove Code-Review Reconciliation Step from Orchestrated Workflows

## Overview

Remove the advisory-only code-review reconciliation step from the orchestrating-workflows skill. The step currently runs between PR review and `executing-qa` in all three chains (feature step 6+N+3, chore step 7, bug step 7), forks a `reviewing-requirements` subagent in code-review mode, and produces findings that are (a) fully superseded by `executing-qa`'s verification and reconciliation loops and (b) lost inside the fork's context. Removing the step eliminates one fork per workflow, simplifies the chain tables, and removes dead advisory-only code from the critical path.

## Feature ID

`FEAT-017`

## GitHub Issue

[#147](https://github.com/lwndev/lwndev-marketplace/issues/147)

## Priority

Medium — The step runs on every orchestrated workflow and costs a full subagent fork (plus model call, audit-trail entry, and findings-handling round-trip), but produces no actionable output because it declares itself advisory and defers every decision to `executing-qa`. The user also never sees the one unique thing it does produce (GitHub issue suggestion drafts) because the findings are trapped in the fork's context and, after FEAT-016, the `details` array it persists only captures severity/category/description — not the draft comment bodies.

## User Story

As a developer running SDLC workflows, I want the orchestrator to skip the advisory code-review reconciliation step so that workflows run faster, avoid an unnecessary fork, and rely on `executing-qa` as the single source of truth for post-PR reconciliation.

## Motivation

The code-review reconciliation step was introduced alongside FEAT-007 to provide a cross-check after PR review. In practice, its three sub-checks divide as follows:

| Sub-step | What it does | Coverage |
|----------|--------------|----------|
| CR2: Test plan staleness | Flags test entries referencing changed APIs/files/behavior | Fully covered by `executing-qa` Step 2 verification loop, which re-verifies every test plan entry against real code via `qa-verifier`. |
| CR3: GitHub issue suggestions | Drafts scope-change / decision / deferred-work comments | Unique to this step, but the drafts never leave the fork. Users who want to post such comments do it manually today. |
| CR4: Requirements drift preview | Compares PR diff against FRs/ACs/edge cases | Fully covered by `executing-qa` Step 3 reconciliation loop, which performs actual document updates (affected files, acceptance criteria, deviation summary) rather than advisory flagging. |

The step explicitly declares itself advisory (see `reviewing-requirements/SKILL.md:276-278`): "This mode is entirely advisory. It does NOT update affected files lists, modify implementation plan phases/deliverables/status, add deviation summaries, or auto-fix requirements documents. Those are handled by `executing-qa` reconciliation." Every orchestrated run emits the trailing message "These are advisory per code-review reconciliation mode. executing-qa reconciliation will handle any actual document updates. Advancing."

Removing the step preserves CR2 and CR4 coverage (via `executing-qa`) and descopes CR3 (manual user workflow). The `reviewing-requirements` skill's code-review reconciliation mode is retained as a standalone capability invocable manually via `/reviewing-requirements {ID} --pr {prNumber}`; only the orchestrator's automatic invocation is removed.

## Functional Requirements

### FR-1: Remove the Step from All Three Chain Step-Sequence Tables

Delete the code-review reconciliation row from the chain tables in `orchestrating-workflows/SKILL.md`:

- **Feature chain**: Remove step `6+N+3` ("Reconcile post-review"). The feature chain becomes `6 + N + 4` steps (down from `6 + N + 5`), with the post-pause sequence becoming: `6+N+1` Create PR → `6+N+2` PAUSE: PR review → `6+N+3` Execute QA → `6+N+4` Finalize.
- **Chore chain**: Remove step 7 ("Reconcile post-review"). The chore chain becomes 8 steps (down from 9): 1 Document chore → 2 Review requirements (standard) → 3 Document QA test plan → 4 Reconcile test plan → 5 Execute chore → 6 PAUSE: PR review → 7 Execute QA → 8 Finalize.
- **Bug chain**: Remove step 7 ("Reconcile post-review"). The bug chain becomes 8 steps (down from 9), mirroring the chore chain.

Update the chain table headers and any prose descriptions of chain length ("has 6 + N + 5 steps" → "has 6 + N + 4 steps"; "has a fixed 9 steps" → "has a fixed 8 steps") throughout the SKILL.md.

### FR-2: Remove Step-Specific Fork Instructions

Delete the fork-instruction blocks for the removed step from `references/step-execution-details.md`:

- Feature chain: Delete the block labeled **Step 6+N+3 — `reviewing-requirements` (code-review reconciliation)**.
- Chore chain: Delete the block labeled **Step 7 — `reviewing-requirements` (code-review reconciliation)**.
- Bug chain: Delete the equivalent block (step 7) and any surrounding prose referring to it.

After removal, the chore-chain fork block list for step numbering (currently "Steps 2, 4, 7, and 9") becomes "Steps 2, 4, and 8" (renumbered per FR-3). The bug-chain list is the same shape.

### FR-3: Renumber Downstream Steps Consistently

Update every reference to downstream step numbers in `SKILL.md`, `references/step-execution-details.md`, `references/chain-procedures.md`, and `references/verification-and-relationships.md` to reflect the new numbering:

- Feature chain: `6+N+4` (Execute QA) → `6+N+3`; `6+N+5` (Finalize) → `6+N+4`.
- Chore chain: `8` (Execute QA) → `7`; `9` (Finalize) → `8`.
- Bug chain: `8` (Execute QA) → `7`; `9` (Finalize) → `8`.

This affects (non-exhaustive; implementation should grep for all occurrences):
- Step number mentions in prose (e.g., "Step 6+N+4 — `executing-qa`")
- The PR-review pause procedure's "restart from the execution step" / "phase loop" references
- The reviewing-requirements findings-handling section's chain-step-to-index table — update the mapping from `feature steps 2/6/6+N+3 map to indices 1/5/6+N+2; chore/bug steps 2/4/7 map to indices 1/3/6` to `feature steps 2/6 map to indices 1/5; chore/bug steps 2/4 map to indices 1/3` (the post-review index row is removed)
- Any verification-checklist items that reference the removed step by number

### FR-4: Remove Findings-Handling Wiring for the Removed Step

Update the Reviewing-Requirements Findings Handling section of `SKILL.md`:

- Change the scope line from "All `reviewing-requirements` fork steps (feature steps 2, 6, 6+N+3; chore steps 2, 4, 7; bug steps 2, 4, 7)..." to "All `reviewing-requirements` fork steps (feature steps 2, 6; chore steps 2, 4; bug steps 2, 4)..."
- Update the chain-step-to-index table (see FR-3).
- Remove the prose note about mode prefixes including `code-review` from the count-extraction regex guidance if it is no longer relevant to remaining call sites. (The `test-plan` prefix case still exists, so the prefix-handling note must be retained — only remove the explicit `code-review` example.)

The `code-review` decision value is no longer written by the orchestrator. No removal is required from `workflow-state.sh` — the `record-model-selection` and `record-findings` subcommands accept `mode` and `decision` as free-form strings; they do not validate against an enum of modes. Old state files that already contain `mode: "code-review"` entries remain valid.

### FR-5: Remove the Fork-Step-Name Map Row

Update the "Fork Step-Name Map" table in `SKILL.md` to remove the `code-review` mode from the `reviewing-requirements` row's description. Before: "Review requirements (standard / test-plan / code-review)". After: "Review requirements (standard / test-plan)".

The step-name itself (`reviewing-requirements`) is unchanged — the two remaining call sites still use it. Only the mode list in the human-readable description is updated.

### FR-6: Update Verification Checklists

Remove references to the code-review reconciliation step from the verification checklists in `references/verification-and-relationships.md`:

- Delete the checklist item (if present) asserting that the post-review reconciliation step was not skipped.
- Delete any checklist item referring to "code-review reconciliation findings handled" or similar.
- Update the skill-relationship tables to remove `reviewing-requirements (code-review mode)` from the per-chain skill tables, leaving only `standard` and `test-plan` modes listed.
- Update the chore-chain and bug-chain prose that asserts "fixed 9-step sequence" to "fixed 8-step sequence" (found near the Chore Chain Checks and Bug Chain Checks sections).

### FR-7: Preserve Code-Review Reconciliation Mode as a Standalone Capability

The `reviewing-requirements` skill's code-review reconciliation mode (`reviewing-requirements/SKILL.md:274-324`) is **retained unchanged**. The orchestrator no longer invokes it automatically, but users can still invoke it manually with `/reviewing-requirements {ID} --pr {prNumber}` for one-off advisory drift reports. No edits to `reviewing-requirements/SKILL.md` are required. Rationale: the capability itself is sound; only its automatic placement in the workflow chain was wrong. Keeping the mode callable preserves the CR2/CR3/CR4 functionality for users who want an ad-hoc check outside the orchestrated flow.

### FR-8: Update Tests

Update the test suite at the top-level `scripts/__tests__/` directory. The two files that cover chain structure and state-file fixtures are:

- `scripts/__tests__/orchestrating-workflows.test.ts` — chain-table and step-sequence assertions
- `scripts/__tests__/workflow-state.test.ts` — state-file fixtures that include `Reconcile post-review` step entries

Required changes:

- Remove tests that specifically exercise the code-review reconciliation step invocation.
- Update chain-length expectations (feature `6+N+5` → `6+N+4`; chore/bug `9` → `8`).
- Update any snapshot or golden-state fixtures to reflect the new step sequence. No fixture should expect a `mode: "code-review"` entry in `modelSelections` for a new workflow, and no fixture should contain a `"Reconcile post-review"` step entry for a newly initialized workflow.

Preserve unchanged:

- `scripts/__tests__/reviewing-requirements.test.ts` — tests that exercise the `reviewing-requirements` code-review mode directly remain valid as the mode itself is unchanged (per FR-7).

## Non-Functional Requirements

### NFR-1: Backwards Compatibility for Existing State Files

Existing workflow state files (`.sdlc/workflows/*.json`) that were written under the old numbering and contain a recorded `Reconcile post-review` step entry (and optionally a `mode: "code-review"` entry in `modelSelections`) remain valid and queryable. No migration script is required because:

- The orchestrator does not use numeric step positions to decide what to execute on resume — it walks the `steps` array and reads each entry's `name`, `skill`, `context`, and `status`.
- A completed workflow with a recorded code-review reconciliation entry is an accurate historical record of what ran at the time; preserving it is correct.

If a workflow is currently **paused** or **failed** at the code-review reconciliation step (either the step is in progress, or the gate is set for findings-decision on that step), the user must either (a) complete the workflow on the old flow before upgrading, or (b) manually edit the state file to drop the step entry and advance past it. The implementation must document this edge case clearly in the release notes / CHORE changelog.

### NFR-2: No Regression in Post-Review Coverage

`executing-qa` must continue to handle every reconciliation area currently covered by the removed step's CR2 (test plan staleness) and CR4 (requirements drift) sub-steps. The FR-7 preservation of the standalone mode ensures CR3 (GitHub issue suggestions) remains accessible as a manual invocation. No functional coverage regression is introduced.

### NFR-3: No Changes Outside the Orchestrator and Its References

The only skill files touched are:
1. `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md`
2. `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md`
3. `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` (if it references the removed step by number — likely minimal)
4. `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/verification-and-relationships.md`
5. `scripts/__tests__/orchestrating-workflows.test.ts` and `scripts/__tests__/workflow-state.test.ts` (test updates only)

Files explicitly NOT touched:
- `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` (per FR-7)
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` (its scope is unchanged)
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` (per FR-4; no enum updates needed)

### NFR-4: Performance

Removing one fork per workflow reduces workflow runtime by the latency of one subagent spawn + one model invocation + one findings-handling round-trip. For a typical orchestrated run, this is on the order of 30–120 seconds saved per workflow. No formal performance target is set — the removal is a strict reduction.

## Dependencies

- FEAT-016 (persist reviewing-requirements findings) — Landed; its `record-findings` subcommand is unchanged by this work. The schema accepts arbitrary `decision` strings, so removing the `code-review` call site is a pure subtraction.
- FEAT-007 (code-review reconciliation mode introduction) — The standalone mode it introduced is preserved per FR-7. This FEAT-017 only removes the automatic orchestrator invocation, not the mode itself.
- CHORE-031 (low-complexity skip for reviewing-requirements steps) — The skip logic currently applies to steps 2 and 4 on chore/bug chains. It does NOT apply to the removed step, so no skip-logic changes are required.

## Edge Cases

1. **Workflow paused at the removed step**: A workflow paused at the old step 6+N+3 / step 7 before upgrading. On resume after upgrade, the orchestrator reads the state file's `steps` array. Because the step entry already exists in the array (created under the old flow), the orchestrator resumes and attempts to execute it — but the step has been removed from the SKILL.md fork instructions. Mitigation: document this in the release notes; instruct users to either finish the workflow on the old flow before upgrading, or manually edit the state file to mark the step complete and re-run resume. The implementation may also add a defensive guard in the orchestrator that recognizes a `reviewing-requirements` / `code-review` mode entry and treats it as a no-op advance on resume, but this is not required.
2. **Workflow paused at PR review**: A workflow paused at the pre-code-review pause (feature `6+N+2` / chore/bug `6`). On resume after upgrade, the orchestrator skips the removed step and proceeds directly to `executing-qa`. No user intervention required — this is the common case and the intended migration path.
3. **Manual invocation of code-review mode**: A user running `/reviewing-requirements {ID} --pr {prNumber}` outside the orchestrator continues to work identically. No change to behavior.
4. **Finding-handling for the removed step in a state file**: If a state file has `findings` or `rerunFindings` recorded on the removed step's entry (from FEAT-016), those entries remain valid and queryable via `jq`. No cleanup is required.
5. **Downstream step-number references in commit messages or docs outside the plugin**: Historical commit messages, PR descriptions, and external docs that reference "step 6+N+3" or "step 7" are not retroactively updated. This is accepted — documentation mirrors the current state; history is preserved as-is.
6. **CHORE-031 skip semantics after renumbering**: The CHORE-031 skip condition targets chore steps 2 and 4 and bug steps 2 and 4 by step-name (`reviewing-requirements`) and mode (`standard`, `test-plan`), not by numeric index. Renumbering downstream steps does not affect the skip logic. No changes required.

## Dependencies and Related Work

- Related to #145 / FEAT-016 (findings persistence) — already landed; not a blocker.
- Related to #139 (findings-handling spiral fix) — already landed; not a blocker.
- Related to #129 (reconciling-drift skill) — out of scope; tracked separately. That work may eventually replace the standalone code-review reconciliation mode (FR-7) with a dedicated skill, but this FEAT-017 does not anticipate or block that migration.

## Testing Requirements

### Unit Tests

- Verify chain-step-sequence tests no longer include an entry for the removed step in any of the three chains.
- Verify chain-length assertions reflect the new totals (feature `6+N+4`, chore `8`, bug `8`).
- Verify findings-handling step-index mapping tests reflect the new `feature steps 2/6 → indices 1/5; chore/bug steps 2/4 → indices 1/3` mapping.
- Verify `record-model-selection` is no longer called with `mode: "code-review"` in any orchestrator-driven test fixture.

### Integration Tests

- Run a full feature chain end-to-end; verify the workflow advances directly from the PR-review pause (post-resume) to `executing-qa` with no intermediate reviewing-requirements fork.
- Run a full chore chain end-to-end; verify the same direct transition.
- Run a full bug chain end-to-end; verify the same direct transition.
- Verify `/reviewing-requirements {ID} --pr {prNumber}` continues to execute the code-review reconciliation mode correctly as a standalone invocation (FR-7).

### Manual Testing

- Run a small feature workflow end-to-end. Inspect the workflow state file and confirm no step entry named "Reconcile post-review" exists.
- Run a small chore workflow end-to-end. Inspect the `modelSelections` audit trail and confirm no entry with `mode: "code-review"` is present.
- Invoke `/reviewing-requirements FEAT-016 --pr 162` manually (using any completed PR) and verify the code-review reconciliation mode still produces its findings list.
- Resume a workflow that was paused at the pre-code-review pause. Verify the orchestrator proceeds directly to `executing-qa`.

## Acceptance Criteria

- [ ] The code-review reconciliation step is removed from all three chain step-sequence tables in `orchestrating-workflows/SKILL.md` (feature, chore, bug).
- [ ] The corresponding step-specific fork instructions are removed from `references/step-execution-details.md`.
- [ ] Downstream steps are renumbered consistently across `SKILL.md`, `references/step-execution-details.md`, `references/chain-procedures.md`, and `references/verification-and-relationships.md` (feature `6+N+4` → `6+N+3`, `6+N+5` → `6+N+4`; chore/bug `8` → `7`, `9` → `8`).
- [ ] The Reviewing-Requirements Findings Handling scope line and chain-step-to-index table are updated to drop the removed step.
- [ ] The chain-step-to-index mapping note in `SKILL.md` (around the Persisting Findings / step-index reference) is updated from `feature steps 2/6/6+N+3 map to indices 1/5/6+N+2; chore/bug steps 2/4/7 map to indices 1/3/6` to `feature steps 2/6 map to indices 1/5; chore/bug steps 2/4 map to indices 1/3`.
- [ ] The Fork Step-Name Map table's description for `reviewing-requirements` drops `code-review` from its mode list.
- [ ] Verification checklists no longer reference the removed step or its findings handling.
- [ ] `reviewing-requirements/SKILL.md` is unchanged (per FR-7); the code-review reconciliation mode remains callable standalone.
- [ ] `executing-qa/SKILL.md` is unchanged.
- [ ] `workflow-state.sh` is unchanged (per NFR-3).
- [ ] Existing workflow state files with historical code-review reconciliation entries remain valid and queryable.
- [ ] The orchestrator's test suite passes with the updated chain lengths and step sequences.
- [ ] A full feature chain end-to-end run produces a state file with no "Reconcile post-review" step entry.
- [ ] A full chore chain end-to-end run produces a state file with 8 step entries (not 9).
- [ ] A full bug chain end-to-end run produces a state file with 8 step entries (not 9).
- [ ] Manual invocation of `/reviewing-requirements {ID} --pr {prNumber}` continues to execute code-review reconciliation mode unchanged.
