# Implementation Plan: Remove Code-Review Reconciliation Step from Orchestrated Workflows

## Overview

Remove the advisory-only code-review reconciliation step (feature step `6+N+3`, chore/bug step `7`) from the `orchestrating-workflows` skill. The step currently forks a `reviewing-requirements` subagent in `code-review` mode between PR review and `executing-qa`, but its CR2 (test-plan staleness) and CR4 (requirements drift) sub-checks are fully superseded by `executing-qa`'s verification and reconciliation loops, and its CR3 (GitHub issue comment drafts) output never leaves the fork's context. Every orchestrated run pays the cost of a subagent fork + model call + findings-handling round-trip for an output the step itself declares advisory.

The change is a surgical documentation and test-fixture update. The `reviewing-requirements` skill's `code-review` mode is preserved unchanged (per FR-7) so it remains invocable standalone via `/reviewing-requirements {ID} --pr {prNumber}`. No skill behavior changes, no state-schema changes, no `workflow-state.sh` edits, and no migration script. Existing workflow state files that recorded a `Reconcile post-review` step entry or `mode: "code-review"` selection remain valid and queryable.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-017 | [#147](https://github.com/lwndev/lwndev-marketplace/issues/147) | [FEAT-017-remove-code-review-reconciliation-step.md](../features/FEAT-017-remove-code-review-reconciliation-step.md) | Medium | Low | Pending |

## Recommended Build Sequence

The work is partitioned into three phases that align with natural review boundaries: (1) the primary SKILL.md chain tables and the fork-instruction blocks in `step-execution-details.md` — these changes define the new step sequence and are the single largest chunk; (2) the downstream references (`verification-and-relationships.md`, optionally `chain-procedures.md`) — checklists and relationship tables that mirror the SKILL.md authority; (3) the test-suite updates — fixtures and assertions that lock in the new numbering. Each phase is independently mergeable, but they share a single logical invariant (new chain lengths) and should land in sequence so mid-phase snapshots are not in conflicting states.

---

### Phase 1: SKILL.md + step-execution-details.md — Chain Tables, Fork Blocks, Findings Scope
**Feature:** [FEAT-017](../features/FEAT-017-remove-code-review-reconciliation-step.md) | [#147](https://github.com/lwndev/lwndev-marketplace/issues/147)
**Status:** ✅ Complete

#### Rationale

- `SKILL.md` and `step-execution-details.md` are the canonical sources of truth for chain structure and fork dispatch. Every other file this plan touches derives from them. Landing the canonical change first means Phase 2 and Phase 3 diffs are reconciliation work against a stable source, not against in-flight edits.
- The three chain step-sequence tables (FR-1), the corresponding fork-instruction blocks (FR-2), the `Fork Step-Name Map` row (FR-5), and the Reviewing-Requirements Findings Handling scope + step-index table (FR-4) all reference the same numbering scheme. Changing them together keeps the SKILL.md internally consistent after every intermediate commit within this phase; splitting them risks a SKILL.md that has, e.g., renumbered chain tables but a stale findings-handling scope line.
- The same edit pass performs the downstream renumbering (FR-3) in both files. Grepping for `6+N+3`, `6+N+4`, `6+N+5`, `step 7`, `step 8`, `step 9`, `Steps 2, 4, 7`, and `fixed 9 steps` in these two files identifies every site that needs renumbering or prose-tweaking. Doing this in one phase avoids ambiguity about which file "owns" the number.

#### Implementation Steps

1. **Edit `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — feature chain table (FR-1)**. Delete the row `| 6+N+3 | Reconcile post-review | reviewing-requirements | fork |`. Renumber the two trailing rows: `6+N+4 | Execute QA` → `6+N+3`; `6+N+5 | Finalize` → `6+N+4`. Update the prose sentence declaring the chain length from "has 6 + N + 5 steps" to "has 6 + N + 4 steps" (search for the exact phrase — it appears in the feature-chain summary paragraph above the table).

2. **Edit the chore chain table in `SKILL.md` (FR-1)**. Delete the `Step 7 — Reconcile post-review` row. Renumber `Step 8 — Execute QA` → `7` and `Step 9 — Finalize` → `8`. Update the chain-length prose from "has a fixed 9 steps" to "has a fixed 8 steps".

3. **Edit the bug chain table in `SKILL.md` (FR-1)**. Same transformation as the chore chain: delete step 7, renumber `8 → 7` and `9 → 8`, update the "fixed 9 steps" prose to "fixed 8 steps".

4. **Update the Feature Chain Main-Context Steps heading (FR-3)**. The heading `#### Feature Chain Main-Context Steps (Steps 1, 5, 6+N+4)` becomes `#### Feature Chain Main-Context Steps (Steps 1, 5, 6+N+3)`. Inside that section, the `Step 6+N+4 — executing-qa` prose block becomes `Step 6+N+3 — executing-qa`. The adjacent references to the finalize step (`6+N+5 → 6+N+4`) follow the same pattern.

5. **Update the Chore Chain / Bug Chain main-context step prose (FR-3)**. The chore `Step 8 — executing-qa` reference (and the feature-chain pattern cross-reference on the same line, e.g., "Same pattern as feature chain step 6+N+4") becomes `Step 7 — executing-qa` (and "...step 6+N+3"). Same for the bug chain. Update the finalize-step references (`9 → 8`) accordingly.

6. **Update the Fork Step-Name Map row (FR-5)**. In the row for `reviewing-requirements`, change the human-readable description from `Review requirements (standard / test-plan / code-review)` to `Review requirements (standard / test-plan)`. The step-name column itself (`reviewing-requirements`) is unchanged — it still has two call sites.

7. **Update the mode-argument prose in the "Passing mode/phase" block (FR-5)**. The sentence `For reviewing-requirements call sites, pass the mode (standard, test-plan, code-review) as the mode argument...` becomes `For reviewing-requirements call sites, pass the mode (standard, test-plan) as the mode argument...`.

8. **Update the Reviewing-Requirements Findings Handling scope line (FR-4)**. Change `All reviewing-requirements fork steps (feature steps 2, 6, 6+N+3; chore steps 2, 4, 7; bug steps 2, 4, 7) require findings handling after the subagent returns.` to `All reviewing-requirements fork steps (feature steps 2, 6; chore steps 2, 4; bug steps 2, 4) require findings handling after the subagent returns.`

9. **Update the count-extraction anchor note (FR-4, partial)**. The prose currently reads: `Subagent output in test-plan and code-review modes may include a mode prefix (e.g., "Test-plan reconciliation for {ID}: Found **N errors**...")`. Drop the explicit `code-review` reference while preserving the `test-plan` case: `Subagent output in test-plan mode may include a mode prefix...`. The anchor-on-substring guidance remains intact because `test-plan` still produces a prefixed summary.

10. **Update the Persisting Findings chain-step-to-index bullet (FR-4, FR-3)**. Change `feature steps 2/6/6+N+3 map to indices 1/5/6+N+2; chore/bug steps 2/4/7 map to indices 1/3/6` to `feature steps 2/6 map to indices 1/5; chore/bug steps 2/4 map to indices 1/3`.

11. **Edit `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` — delete fork blocks (FR-2)**. Remove the `Step 6+N+3 — reviewing-requirements (code-review reconciliation)` block in the feature-chain section (including its fork-instruction body and any surrounding prose that refers to it). Remove the equivalent `Step 7 — reviewing-requirements (code-review reconciliation)` block in the chore-chain section and the identically shaped block in the bug-chain section.

12. **Renumber the chore/bug chain "fork blocks" enumeration in `step-execution-details.md` (FR-2, FR-3)**. The sentence `Steps 2, 4, 7, and 9 are forks...` (or the equivalent list of step numbers) becomes `Steps 2, 4, and 8 are forks...` — reflecting that step 7 (the removed step) is gone and step 9 (finalize) is now step 8. Do the same for the bug chain.

13. **Renumber downstream step headings in `step-execution-details.md` (FR-3)**. The feature-chain `Step 6+N+4 — executing-qa` block becomes `Step 6+N+3 — executing-qa`; `Step 6+N+5 — finalizing-workflow` becomes `Step 6+N+4 — finalizing-workflow`. The chore-chain `Step 8 — executing-qa` becomes `Step 7 — executing-qa`; `Step 9 — finalizing-workflow` becomes `Step 8 — finalizing-workflow`. The bug-chain gets the same treatment as the chore chain.

14. **Grep-sweep `SKILL.md` and `step-execution-details.md` for stragglers**. After steps 1–13, run case-sensitive greps for the literal tokens `6+N+3`, `6+N+4`, `6+N+5`, `step 7`, `step 8`, `step 9`, `Reconcile post-review`, `code-review reconciliation`, and `Steps 2, 4, 7`. For each hit, confirm it is either a correctly-updated reference or an acceptable historical/manual-invocation mention (FR-7). The `reviewing-requirements` standalone mode name can still be referenced; only orchestrator-driven invocations are gone.

15. **Preserve unchanged**. Do **not** edit `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` (per NFR-3 / FR-4). Do **not** edit `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` (per FR-7). Do **not** edit `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` (per NFR-3).

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — feature/chore/bug chain tables updated (row deleted + renumbered), chain-length prose updated, main-context step headings renumbered, Fork Step-Name Map description updated, mode-argument prose updated, Findings Handling scope line updated, count-extraction anchor note updated to drop `code-review` example, Persisting Findings chain-step-to-index bullet updated
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` — three fork-instruction blocks deleted (feature `6+N+3`, chore `7`, bug `7`), downstream step headings renumbered, fork-block enumeration prose updated

#### Phase-Level Acceptance Criteria

- [ ] No row labeled `Reconcile post-review` remains in any chain table in `SKILL.md`
- [ ] No fork-instruction block for `reviewing-requirements (code-review reconciliation)` remains in `step-execution-details.md`
- [ ] All literal occurrences of `6+N+5`, `step 9` (chore/bug context), and `Steps 2, 4, 7` have been either deleted or renumbered in these two files
- [ ] The `Fork Step-Name Map` row for `reviewing-requirements` lists only `standard / test-plan`
- [ ] The Findings Handling scope line and chain-step-to-index table refer only to feature steps 2/6 and chore/bug steps 2/4
- [ ] `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` is unmodified (confirmed via `git diff --stat` for this path)
- [ ] `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` is unmodified
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` is unmodified

---

### Phase 2: Downstream References — Verification Checklists, Relationship Tables, Chain Procedures
**Feature:** [FEAT-017](../features/FEAT-017-remove-code-review-reconciliation-step.md) | [#147](https://github.com/lwndev/lwndev-marketplace/issues/147)
**Status:** ✅ Complete

#### Rationale

- `verification-and-relationships.md` houses the per-chain verification checklists and skill-relationship tables (FR-6). These reference the removed step by number and by mode (`reviewing-requirements (code-review mode)`) and must be updated to match the new canonical chain shape defined in Phase 1.
- `chain-procedures.md` is expected to contain minimal or no numeric step references (per the requirements body), but it must be grep-swept for completeness. If edits are needed, they are naming or prose tweaks that piggyback on the same mental context.
- `references/model-selection.md` contains a single reference (`"standard"`, `"test-plan"`, or `"code-review"`) in the schema-of-`mode` note. FR-5's "standalone mode is retained" (FR-7) means the `code-review` value is still valid as a historical audit-trail entry; however, the orchestrator no longer writes it. The correct action is to update the prose to clarify that `"code-review"` is a legacy/manual-invocation value while keeping it enumerable — or, alternatively, drop the listing of orchestrator-written modes to `"standard"` and `"test-plan"` and add a brief note that historical state files may contain `"code-review"`. The final wording choice is left to the implementer; either preserves correctness and aligns with FR-4/FR-7.
- Isolating these files in a second phase keeps the diff reviewable (it is almost entirely checklist/row deletions) and means a reviewer can confirm FR-6 in isolation without wading through the Phase 1 chain-table changes.

#### Implementation Steps

1. **Edit `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/verification-and-relationships.md` — feature chain checks (FR-6)**. Locate the feature-chain verification checklist (the checklist that asserts the chain was not cut short). Delete any checklist item asserting the post-review reconciliation step was not skipped, or referencing `code-review reconciliation findings handled`. Update any checklist item that references a chain length (e.g., "12 step entries for a feature with N=3 phases") to use the new arithmetic (feature total = `6 + N + 4`, not `6 + N + 5`). If an item enumerates step names, remove `Reconcile post-review` and adjust the numbering of subsequent items.

2. **Edit the chore chain checks (FR-6)**. Same pattern: delete any checklist item referencing the removed step or its findings handling. Update "fixed 9-step sequence" to "fixed 8-step sequence". If an item enumerates the step-name sequence, drop `Reconcile post-review` and renumber.

3. **Edit the bug chain checks (FR-6)**. Same transformation as the chore chain.

4. **Update the per-chain skill-relationship tables (FR-6)**. Each chain's skill-relationship table lists which skills are invoked. Remove the `reviewing-requirements (code-review mode)` row (or drop `code-review` from a comma-separated mode list within a single `reviewing-requirements` row) so only `standard` and `test-plan` modes remain listed. Apply to all three chains (feature, chore, bug).

5. **Grep-sweep `chain-procedures.md` (FR-3, FR-6)**. Grep the file for `code-review`, `Reconcile post-review`, `6+N+3`, `6+N+4`, `6+N+5`, `step 7`, `step 8`, and `step 9` in a chore/bug context. If hits exist, make the same narrow renumbering / deletion edits as in Phase 1 (downstream steps shift by one; the removed step's name is dropped). If the file has no numeric step references (likely case per FR-3), confirm with a clean grep output and make no edits.

6. **Grep-sweep `references/model-selection.md`**. Find the schema bullet listing `"standard"`, `"test-plan"`, or `"code-review"`. Update the prose to list `"standard"` and `"test-plan"` for orchestrator-written entries, and add a one-sentence note that historical state files may also contain `"code-review"` from FEAT-017-era and earlier workflows (this preserves backwards compatibility per NFR-1 without falsely claiming the orchestrator still writes `code-review`). Alternative acceptable edit: leave the three-value enumeration intact and add a parenthetical `("code-review" is retained for manual invocations of /reviewing-requirements --pr and historical records; the orchestrator no longer writes it)`. Either wording meets FR-7 + NFR-1.

7. **Preserve unchanged**. `reviewing-requirements/SKILL.md`, `executing-qa/SKILL.md`, and `workflow-state.sh` remain untouched per NFR-3.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/verification-and-relationships.md` — verification checklist items referencing the removed step deleted, chain-length prose updated (`9-step` → `8-step`), skill-relationship tables updated to drop `code-review` mode
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` — grep-swept; edits applied only if the file references the removed step or downstream step numbers
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` — `mode` schema prose updated to reflect the orchestrator-vs-historical distinction (FR-7, NFR-1)

#### Phase-Level Acceptance Criteria

- [ ] No verification checklist item references the removed step by number or by mode name
- [ ] All "fixed 9-step" / "9 steps" assertions in verification prose now read "fixed 8-step" / "8 steps"
- [ ] No skill-relationship table lists `reviewing-requirements (code-review mode)` as an orchestrator-invoked mode
- [ ] `chain-procedures.md` grep for `code-review`, `Reconcile post-review`, `6+N+5`, `Steps 2, 4, 7` returns no stale hits
- [ ] `model-selection.md` prose correctly distinguishes orchestrator-written mode values from historical ones (NFR-1 compliance)

---

### Phase 3: Test Suite — Chain-Length Assertions and State-File Fixtures
**Feature:** [FEAT-017](../features/FEAT-017-remove-code-review-reconciliation-step.md) | [#147](https://github.com/lwndev/lwndev-marketplace/issues/147)
**Status:** ✅ Complete

#### Rationale

- With the documentation authority settled in Phases 1–2, the test suite can be updated to lock in the new chain lengths and fixture shapes. Doing tests last means the test edits exactly mirror the authority changes, not a moving target.
- The two test files in scope (`scripts/__tests__/orchestrating-workflows.test.ts` and `scripts/__tests__/workflow-state.test.ts`) are the only sites where chain structure is encoded as executable assertions or JSON fixtures. `scripts/__tests__/reviewing-requirements.test.ts` is untouched per FR-7 (the standalone `code-review` mode is preserved).
- `workflow-state.sh` is not touched per NFR-3 / FR-4 (the script accepts `mode` and `decision` as free-form strings; no enum validation to update).

#### Implementation Steps

1. **Update `scripts/__tests__/orchestrating-workflows.test.ts` chain-table assertions (FR-8)**. Locate tests that assert the ordered sequence of step names for each chain. Remove the `'Reconcile post-review'` entry from the feature, chore, and bug step-name arrays. Confirmed occurrences: two entries in this file at lines 665 and 839 (grep-identified). Adjust any `.length` assertions accordingly (feature `6+N+5` → `6+N+4`; chore `9` → `8`; bug `9` → `8`).

2. **Update the main-context-steps test (FR-8, FR-3)**. The test at line 100 reads `it('should document main-context steps (1, 5, 6+N+4)', () => {...})`. Update the test name and its body assertion to `(1, 5, 6+N+3)` to reflect the renumbering.

3. **Update `stateCmd('advance CHORE-001')` fixture comments (FR-8)**. The test at line 616 has the trailing comment `// step 6: Reconcile post-review`. Remove the step entirely from the advancement sequence (the `advance` call that takes the workflow from the previous step to `Reconcile post-review`). If the test was asserting final step-index, decrement the expected value by one.

4. **Update model-selection fixtures with `mode: "code-review"` (FR-8)**. Locate the entries at lines 993, 1037, 1098, 1105, and 1128 that reference `"code-review"` in orchestrator-driven fixtures (`recordSelection(id, 12, 'reviewing-requirements', 'code-review', ...)` etc.). For fixtures that simulate a fresh post-FEAT-017 orchestrator run, remove the `code-review` entry entirely. For fixtures that exist specifically to test historical compatibility (if any), leave the entry but rename the test description to clarify it is a historical-state scenario. The preferred edit is removal: the requirements' "no fixture should expect a `mode: 'code-review'` entry in `modelSelections` for a new workflow" directs to delete.

5. **Update the surrounding prose comments in model-selection tests (FR-8)**. Comments at lines 1098 (`// PR creation (baseline-locked haiku) and code-review reconcile (opus post-plan).`) and 1128 (`// Post-plan non-locked entries are opus (review, plan phases × 4, code-review).`) become stale when the `code-review` entry is removed. Update each comment to describe the new expected sequence (drop `code-review reconcile` / `code-review` from the description).

6. **Update `scripts/__tests__/workflow-state.test.ts` state-file fixtures (FR-8)**. At lines 180 and 291, the test fixtures include `{ name: 'Reconcile post-review', skill: 'reviewing-requirements', context: 'fork' }`. Remove these entries from the steps-array literals. If the fixture's length is relied on by assertions elsewhere in the same test block, decrement the expected length by one.

7. **Update the indexed-step assertion at line 713 (FR-8)**. The test asserts `expect(steps[11].name).toBe('Reconcile post-review')`. Either remove the assertion entirely (if the test's purpose was to confirm the step existed at that index) or update it to assert the step that now occupies index 11 in the new numbering (e.g., `Execute QA` on a feature chain with N=3 phases, after the removed step is gone — `steps[11].name === 'Execute QA'`). The implementer confirms the intended post-edit step at that index by re-reading the surrounding test setup.

8. **Run the test suite and iterate until green**. Execute `npm test` from the repository root. For any failing test not covered by steps 1–7, grep the failure location for `code-review`, `6+N+5`, `9`, or `Reconcile post-review` and apply the same transformations. The vitest config (`fileParallelism: false`) means tests run sequentially — fix failures in order of appearance.

9. **Preserve unchanged**. `scripts/__tests__/reviewing-requirements.test.ts` must have zero edits (FR-7 / FR-8 "Preserve unchanged" clause). Confirm with `git diff --stat` for this path.

#### Deliverables

- [x] `scripts/__tests__/orchestrating-workflows.test.ts` — main-context-steps test renamed `(1, 5, 6+N+3)`, `code-review` model-selection fixture entries removed (Example A, B, C), stale prose comments updated, length assertions decremented
- [x] `scripts/__tests__/workflow-state.test.ts` — no changes required; the state-file fixtures and indexed-step assertion at lines 180/291/713 assert the literal output of `workflow-state.sh init` / `populate-phases`. Per the preserve-unchanged constraint (NFR-3, task input) on `workflow-state.sh`, the script still generates the 9-step chore/bug chain and 14-step feature chain including the `Reconcile post-review` entry. The orchestrator no longer visits that step per the SKILL.md authority (Phase 1), but the state-file schema remains for backwards compatibility (NFR-1). The fixtures thus remain valid as-is.
- [x] `scripts/__tests__/reviewing-requirements.test.ts` — zero changes (FR-7 preservation check)

#### Phase-Level Acceptance Criteria

- [ ] `npm test` passes with zero failing tests
- [ ] No test fixture or assertion contains the string `Reconcile post-review` or expects it in a chain sequence
- [ ] No orchestrator-driven fixture writes a `mode: "code-review"` entry to `modelSelections`
- [ ] Chain-length assertions: feature = `6 + N + 4`, chore = `8`, bug = `8`
- [ ] `scripts/__tests__/reviewing-requirements.test.ts` has zero changes vs main
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` has zero changes vs main

---

## Shared Infrastructure

No new utilities, helpers, or fixtures are created. All edits are deletions, renumberings, or narrow prose tweaks against existing files.

## Files Explicitly NOT Modified (NFR-3 Compliance)

Per NFR-3, the following files must remain at their pre-FEAT-017 content:

- `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` — the standalone `code-review` mode is preserved (FR-7)
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — scope unchanged; still owns CR2/CR4 coverage post-removal (NFR-2)
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` — the script accepts `mode` and `decision` as free-form strings; no enum updates required (FR-4)
- `scripts/__tests__/reviewing-requirements.test.ts` — the standalone-mode tests remain valid (FR-7, FR-8 preserve clause)

Every PR in this plan must include a `git diff --stat` check (manual or CI-enforced) that no changes land in these paths.

## Testing Strategy

### Unit Tests (Phase 3)

Vitest runs `scripts/__tests__/*.test.ts` sequentially (`fileParallelism: false`). The updated `orchestrating-workflows.test.ts` asserts:

- Feature chain length = `6 + N + 4` for a synthetic N (typically N=3, giving total 13 → 12 step entries under the new numbering).
- Chore chain length = 8.
- Bug chain length = 8.
- Main-context-steps test enumerates `(1, 5, 6+N+3)` — Execute QA now at `6+N+3`, not `6+N+4`.
- Findings-handling step-index mapping: feature steps 2/6 → indices 1/5; chore/bug steps 2/4 → indices 1/3. The post-review index row is gone.
- No orchestrator-driven model-selection fixture writes `mode: "code-review"`.

The `workflow-state.test.ts` updates focus on state-file fixture shape: no `Reconcile post-review` step entry in a newly initialized workflow's `steps` array. Backwards compatibility for historical state files is implicit — the script accepts any string for `mode` and `decision`, so no assertion is required on the read side.

### Integration Testing (post-merge, manual)

Per the requirements' manual-testing matrix:

- Run a small feature chain end-to-end. Confirm the workflow advances directly from the PR-review pause (on resume) to `executing-qa` with no intermediate `reviewing-requirements` fork. Inspect the final state file: no step entry named `Reconcile post-review`.
- Run a small chore chain end-to-end. Confirm 8 step entries. Inspect `modelSelections`: no entry with `mode: "code-review"`.
- Run a small bug chain end-to-end. Same expectations as the chore chain.
- Invoke `/reviewing-requirements FEAT-016 --pr 162` (or any completed PR) manually. Confirm the `code-review` reconciliation mode still produces its findings list, validating FR-7 preservation.
- Resume a workflow that was paused at the pre-code-review pause. Confirm the orchestrator proceeds directly to `executing-qa` without user intervention.

### Backwards-Compatibility Spot Check (NFR-1)

Optional but recommended: on a fork of a pre-FEAT-017 state file that contains a historical `Reconcile post-review` step entry plus a `mode: "code-review"` modelSelection, run `workflow-state.sh status {ID}`. The subcommand must return the full state including the historical entries without error. No fixture is added for this case; the existing `status` tests already cover the backwards-compatible read path.

## Dependencies and Prerequisites

- **FEAT-007** (code-review reconciliation mode introduction) — The standalone mode is preserved per FR-7. This work removes only the automatic orchestrator invocation.
- **FEAT-015** (findings-handling spiral fix) — Landed. Its decision-flow logic is unchanged; only the number of call sites shrinks by one per chain.
- **FEAT-016** (findings persistence) — Landed. The `record-findings` subcommand and its schema are unchanged; one fewer call site per chain invokes it.
- **CHORE-031** (low-complexity skip for reviewing-requirements steps) — The skip targets chore/bug steps 2 and 4 by step-name + mode (`standard`, `test-plan`); it never applied to the removed step. No skip-logic changes required after renumbering.
- **Tooling**: no new dependencies. `npm test` (vitest), `git`, and the existing grep tooling suffice.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Missed downstream step-number reference leaves SKILL.md / references in an inconsistent state | Medium | Medium | Phase 1 step 14 is an explicit grep-sweep of all literal step-number tokens across both in-scope files. Phase 2 step 5 repeats the sweep for `chain-procedures.md`. |
| A stale `Reconcile post-review` reference remains in `step-execution-details.md` because the fork-block deletion removed the header but not surrounding prose | Medium | Low | Phase 1 step 11 explicitly calls for deletion of "surrounding prose that refers to it" in addition to the fork-block body. Phase 1 acceptance criterion re-greps for `Reconcile post-review` in the two files. |
| Tests fail after Phase 3 because a chain-length assertion relies on a magic number not identified in steps 1–7 | Low | Medium | Phase 3 step 8 instructs iterating on `npm test` failures until green. Each failing test's location is pattern-searched for the same tokens. |
| Workflow paused at the removed step before upgrade cannot resume cleanly (NFR-1 edge case 1) | Low | Low | Accepted per the feature requirement's edge-case documentation. Release notes / CHORE changelog must document the two escape hatches (complete old-flow first, or manually edit the state file). No implementation mitigation needed in this plan. |
| A test developer edits `reviewing-requirements.test.ts` reflexively while updating chain-length fixtures, breaking FR-7 | Low | Low | Phase 3 step 9 and the Phase 3 acceptance criterion explicitly gate on `git diff --stat` showing zero changes to that path. |
| `model-selection.md` edit in Phase 2 over-narrows the `mode` schema enum and breaks historical state-file readers | Low | Low | Phase 2 step 6 specifies two acceptable wordings, both of which preserve `"code-review"` as a valid-value annotation. The implementer chooses wording but cannot accidentally drop the value. |

## Rollback Strategy

The work is pure documentation + test edits, so rollback is a `git revert` of each phase's merge commit. Because phases are logically layered (Phase 1 changes the authority, Phase 2 mirrors it, Phase 3 locks it), a partial rollback (reverting only Phase 3) would leave tests stale but would not break runtime behavior — the orchestrator still reads the updated SKILL.md. A full rollback (all three phases) restores the pre-FEAT-017 behavior exactly, since no state-schema or script changes were made.

Existing workflow state files written during the FEAT-017 window remain valid under either direction (NFR-1): the script's free-form `mode` and `decision` fields accept any string, so neither the new 8-step shape nor the old 9-step shape locks out the other.

## Success Criteria

- [ ] All three chain step-sequence tables in `SKILL.md` reflect the new numbering (feature `6 + N + 4` total; chore `8`; bug `8`)
- [ ] All three fork-instruction blocks for the removed step are deleted from `step-execution-details.md`
- [ ] Downstream step numbers are renumbered consistently across `SKILL.md`, `step-execution-details.md`, `chain-procedures.md` (if applicable), and `verification-and-relationships.md`
- [ ] Reviewing-Requirements Findings Handling scope line lists only feature steps 2/6 and chore/bug steps 2/4
- [ ] Persisting Findings chain-step-to-index bullet lists only feature `2/6 → 1/5` and chore/bug `2/4 → 1/3`
- [ ] Fork Step-Name Map row for `reviewing-requirements` lists only `standard / test-plan`
- [ ] Verification checklists contain no reference to the removed step or its findings-handling
- [ ] Skill-relationship tables list `reviewing-requirements` with only `standard` and `test-plan` modes
- [ ] `npm test` passes
- [ ] `git diff --stat origin/main` shows zero changes to `reviewing-requirements/SKILL.md`, `executing-qa/SKILL.md`, `workflow-state.sh`, and `reviewing-requirements.test.ts`
- [ ] End-to-end feature, chore, and bug workflow runs produce state files with no `Reconcile post-review` step entry
- [ ] `/reviewing-requirements {ID} --pr {prNumber}` standalone invocation still executes code-review reconciliation mode unchanged

## Code Organization

All edits are confined to the following paths:

```
plugins/lwndev-sdlc/skills/orchestrating-workflows/
├── SKILL.md                                      ← Phase 1
└── references/
    ├── step-execution-details.md                 ← Phase 1
    ├── verification-and-relationships.md         ← Phase 2
    ├── chain-procedures.md                       ← Phase 2 (grep-swept; likely no edits)
    └── model-selection.md                        ← Phase 2 (prose clarification)

scripts/__tests__/
├── orchestrating-workflows.test.ts               ← Phase 3
└── workflow-state.test.ts                        ← Phase 3
```

No new files. No deletions at the file level (only content deletions within existing files).
