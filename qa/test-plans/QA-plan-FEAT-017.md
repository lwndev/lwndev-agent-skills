# QA Test Plan: Remove Code-Review Reconciliation Step from Orchestrated Workflows

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-FEAT-017 |
| **Requirement Type** | FEAT |
| **Requirement ID** | FEAT-017 |
| **Source Documents** | `requirements/features/FEAT-017-remove-code-review-reconciliation-step.md`, `requirements/implementation/FEAT-017-remove-code-review-reconciliation-step.md` |
| **Date Created** | 2026-04-18 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/orchestrating-workflows.test.ts` | Chain-table step sequences, main-context steps, findings-handling step-index mapping, model-selection fixtures | PENDING |
| `scripts/__tests__/workflow-state.test.ts` | State-file initialization, `advance`/`pause`/`resume` behaviors, `record-findings` / `record-model-selection` subcommands, state-file fixtures | PENDING |
| `scripts/__tests__/reviewing-requirements.test.ts` | Standalone `reviewing-requirements` skill tests (standard / test-plan / code-review modes) — **MUST remain unchanged per FR-7** | PENDING |
| `scripts/__tests__/executing-qa.test.ts` | `executing-qa` verification + reconciliation loops (supersedes CR2/CR4 per NFR-2) | PENDING |
| `scripts/__tests__/build.test.ts` | Plugin validation pipeline | PENDING |
| `scripts/__tests__/creating-implementation-plans.test.ts` | Plan generation | PENDING |
| `scripts/__tests__/implementing-plan-phases.test.ts` | Phase execution | PENDING |
| `scripts/__tests__/executing-chores.test.ts` | Chore execution | PENDING |
| `scripts/__tests__/executing-bug-fixes.test.ts` | Bug-fix execution | PENDING |
| `scripts/__tests__/documenting-qa.test.ts` | QA-plan generation | PENDING |
| `scripts/__tests__/managing-work-items.test.ts` | Issue-tracker integration | PENDING |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| Feature chain step-sequence no longer includes `Reconcile post-review`; length = `6 + N + 4` | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-1, FR-8, AC "all three chain tables" | High | PENDING |
| Chore chain step-sequence no longer includes `Reconcile post-review`; length = 8 | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-1, FR-8, AC "chore chain 8 step entries" | High | PENDING |
| Bug chain step-sequence no longer includes `Reconcile post-review`; length = 8 | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-1, FR-8, AC "bug chain 8 step entries" | High | PENDING |
| Main-context-steps test renamed from `(1, 5, 6+N+4)` → `(1, 5, 6+N+3)` with assertions updated | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-3, FR-8 | High | PENDING |
| `advance CHORE-001` sequence no longer includes a step transitioning to `Reconcile post-review` | `scripts/__tests__/orchestrating-workflows.test.ts:616` | FR-8 | High | PENDING |
| Model-selection fixtures at lines 993/1037/1098/1105/1128 no longer emit `mode: "code-review"` for fresh workflows | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-8 AC "no fixture should expect `mode: 'code-review'`" | High | PENDING |
| Comment at line 1098 (`// PR creation ... and code-review reconcile`) and line 1128 (`// Post-plan non-locked entries ... code-review`) updated to match new fixture shape | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-8 (stale-prose cleanup) | Medium | PENDING |
| State-file fixture at line 180 has `Reconcile post-review` step entry removed | `scripts/__tests__/workflow-state.test.ts:180` | FR-8 | High | PENDING |
| State-file fixture at line 291 has `Reconcile post-review` step entry removed | `scripts/__tests__/workflow-state.test.ts:291` | FR-8 | High | PENDING |
| Indexed-step assertion at line 713 (`expect(steps[11].name).toBe('Reconcile post-review')`) updated or removed | `scripts/__tests__/workflow-state.test.ts:713` | FR-8 | High | PENDING |
| Findings-handling step-index mapping covers only feature 2/6→1/5 and chore/bug 2/4→1/3 | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-3, FR-4, AC "chain-step-to-index mapping note" | Medium | PENDING |
| Full `npm test` passes with zero failing tests | All test files under `scripts/__tests__/` | FR-8, Phase 3 AC | High | PENDING |
| `reviewing-requirements.test.ts` has zero changes vs main (FR-7 preservation check) | `scripts/__tests__/reviewing-requirements.test.ts` | FR-7, FR-8 preserve-unchanged clause | High | PENDING |
| `workflow-state.sh` has zero changes vs main (NFR-3 preservation check) | `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` | NFR-3, FR-4 | High | PENDING |
| `reviewing-requirements/SKILL.md` has zero changes vs main (FR-7 preservation check) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-7, NFR-3 | High | PENDING |
| `executing-qa/SKILL.md` has zero changes vs main (NFR-3 preservation check) | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | NFR-3 | High | PENDING |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| End-to-end feature chain no longer spawns a `reviewing-requirements` fork in `code-review` mode between PR-review pause and `executing-qa` | Integration surface: `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` feature chain step-sequence table | FR-1, Edge Case 2, AC "full feature chain end-to-end" | Manual end-to-end run on a small feature (per requirements Manual Testing matrix). Unit test in `orchestrating-workflows.test.ts` asserts the chain sequence shape. |
| End-to-end chore chain no longer spawns the same fork between PR-review pause and `executing-qa` | Integration surface: same file, chore chain section | FR-1, AC "chore chain end-to-end" | Manual chore-chain run + chain-sequence unit test. |
| End-to-end bug chain no longer spawns the same fork between PR-review pause and `executing-qa` | Integration surface: same file, bug chain section | FR-1, AC "bug chain end-to-end" | Manual bug-chain run + chain-sequence unit test. |
| Workflow resume from pre-code-review PR-review pause flows directly into `executing-qa` with no user intervention | State-file replay path: `workflow-state.sh resume` + orchestrator step-dispatch | FR-1, Edge Case 2, AC "resume ... proceeds directly to `executing-qa`" | Manual test: pause a workflow at PR-review, upgrade orchestrator, re-invoke — verify no additional fork is spawned. |
| Standalone `/reviewing-requirements {ID} --pr {prNumber}` invocation continues to execute code-review reconciliation mode unchanged | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md:274-324` (unchanged code path) | FR-7, AC "standalone invocation still executes code-review reconciliation mode" | Manual test with any completed PR. `reviewing-requirements.test.ts` remains in place as the automated cover. |
| Historical state files with `"Reconcile post-review"` step entries or `mode: "code-review"` modelSelection entries remain queryable via `workflow-state.sh status` | `workflow-state.sh` read path (free-form `mode`/`decision` strings) | NFR-1, Edge Case 4 | Backwards-compat spot check: run `status` on a pre-FEAT-017 state file; confirm JSON output contains historical entries without error. No new automated test required — existing `status` tests cover the read path. |
| Workflow paused at the removed step (Edge Case 1) cannot auto-resume; user must complete on old flow or hand-edit state | Release-notes / CHORE changelog documentation path | NFR-1, Edge Case 1 | Accepted per requirement. Manual verification that release notes document the two escape hatches. No automated test. |
| `verification-and-relationships.md` checklist no longer lists the removed step | Reference document | FR-6, AC "Verification checklists no longer reference the removed step" | Manual diff review of the reference file pre/post change. Optional lint: grep the file for `Reconcile post-review` / `code-review reconciliation` — should return zero hits. |
| `chain-procedures.md` grep-sweep returns no stale `6+N+5`, `step 7`, `Reconcile post-review` hits | Reference document | FR-3, Phase 2 AC | Manual grep during QA. |
| `model-selection.md` `mode` schema prose correctly distinguishes orchestrator-written values from historical ones | Reference document | FR-7, NFR-1, Phase 2 AC | Manual read + grep for `"code-review"` in the file; confirm the prose preserves the value as valid (for historical records) while clarifying the orchestrator no longer writes it. |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| FR-1 | Remove step row from all three chain step-sequence tables | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — feature/chore/bug chain tables | Grep for `Reconcile post-review` → 0 hits in chain tables; grep for `6+N+5` → 0 hits; grep for `fixed 9 steps` → 0 hits | PENDING |
| FR-2 | Remove step-specific fork-instruction blocks | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` | Grep for `code-review reconciliation` block heading → 0 hits; unit test assertion on chain-sequence shape | PENDING |
| FR-3 | Renumber downstream steps consistently | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md`, `references/step-execution-details.md`, `references/chain-procedures.md`, `references/verification-and-relationships.md` | Grep sweep for `6+N+4`, `6+N+5`, `step 8`, `step 9` (in chore/bug context) → only correctly-renumbered references remain; unit test: main-context-steps test renamed `(1, 5, 6+N+3)` | PENDING |
| FR-4 | Drop findings-handling wiring for the removed step | `SKILL.md` — Reviewing-Requirements Findings Handling scope line + chain-step-to-index bullet | String match on the updated scope line: `feature steps 2, 6; chore steps 2, 4; bug steps 2, 4`; string match on the updated index bullet: `feature steps 2/6 map to indices 1/5; chore/bug steps 2/4 map to indices 1/3` | PENDING |
| FR-5 | Drop `code-review` mode from Fork Step-Name Map row | `SKILL.md` — Fork Step-Name Map table row for `reviewing-requirements` + accompanying mode-argument prose | String match on `Review requirements (standard / test-plan)` and on `pass the mode (standard, test-plan) as the mode argument` | PENDING |
| FR-6 | Remove references from verification checklists and update prose | `references/verification-and-relationships.md` | Grep for `code-review reconciliation`, `Reconcile post-review`, `9-step sequence` → 0 hits (except preserved historical notes, if any); manual review of skill-relationship tables | PENDING |
| FR-7 | Preserve `reviewing-requirements` code-review mode | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` (unchanged) | `git diff --stat origin/main -- plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` shows zero changes; manual invocation test of `/reviewing-requirements {ID} --pr {N}` | PENDING |
| FR-8 | Update the orchestrator test suite | `scripts/__tests__/orchestrating-workflows.test.ts`, `scripts/__tests__/workflow-state.test.ts` | Targeted assertion updates + `npm test` passes with zero failures; grep test files for `Reconcile post-review` / `code-review` in orchestrator-scope fixtures → 0 hits | PENDING |

## Deliverable Verification

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| SKILL.md chain tables updated (all 3 chains), chain-length prose updated, main-context step headings renumbered, Fork Step-Name Map description updated, mode-argument prose updated, Findings Handling scope line updated, count-extraction anchor note updated, Persisting Findings chain-step-to-index bullet updated | Phase 1 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | PENDING |
| Three fork-instruction blocks deleted (feature `6+N+3`, chore `7`, bug `7`), downstream step headings renumbered, fork-block enumeration prose updated | Phase 1 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` | PENDING |
| Verification checklist items referencing the removed step deleted, chain-length prose updated (`9-step` → `8-step`), skill-relationship tables updated to drop `code-review` mode | Phase 2 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/verification-and-relationships.md` | PENDING |
| Grep-swept; edits applied only if the file references the removed step or downstream step numbers | Phase 2 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` | PENDING |
| `mode` schema prose updated to reflect the orchestrator-vs-historical distinction | Phase 2 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` | PENDING |
| Chain-table step-name assertions updated, chain-length assertions updated, main-context-steps test renamed `(1, 5, 6+N+3)`, `code-review` model-selection fixture entries removed, stale prose comments updated | Phase 3 | `scripts/__tests__/orchestrating-workflows.test.ts` | PENDING |
| State-file fixtures at lines 180 and 291 have `Reconcile post-review` entry removed, indexed-step assertion at line 713 updated or removed | Phase 3 | `scripts/__tests__/workflow-state.test.ts` | PENDING |
| Zero changes (FR-7 preservation check) | Phase 3 | `scripts/__tests__/reviewing-requirements.test.ts` | PENDING |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
