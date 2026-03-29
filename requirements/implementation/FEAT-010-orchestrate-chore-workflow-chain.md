# Implementation Plan: Orchestrate Chore Workflow Chain

## Overview

Add chore workflow chain support to the existing `orchestrating-workflows` skill. The chore chain is a 9-step fixed sequence (no phase loop, no plan-approval pause) with a single PR-review pause point. This builds entirely on the shared orchestration infrastructure from FEAT-009 -- the state script, stop hook, Agent-tool forking pattern, and resume mechanism are already in place. The work involves adding a `generate_chore_steps` function to the state script, removing the "not yet implemented" guard for `chore` in `init`, and extending the SKILL.md with chore chain documentation and execution procedures.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-010 | [#90](https://github.com/lwndev/lwndev-marketplace/issues/90) | [FEAT-010-orchestrate-chore-workflow-chain.md](../features/FEAT-010-orchestrate-chore-workflow-chain.md) | High | Medium | In Progress |

## Recommended Build Sequence

### Phase 1: State Script -- Chore Chain Support
**Feature:** [FEAT-010](../features/FEAT-010-orchestrate-chore-workflow-chain.md) | [#90](https://github.com/lwndev/lwndev-marketplace/issues/90)
**Status:** ✅ Complete

#### Rationale
- Foundation that the SKILL.md procedures depend on -- `init CHORE-XXX chore` must produce a valid 9-step state file before the orchestrator can reference it
- The state script currently returns "not yet implemented" for `chore`; this is the minimal change needed to unblock everything else
- Real code (bash + jq) that can be unit-tested independently before modifying the skill document
- All existing state commands (`status`, `advance`, `pause`, `resume`, `fail`, `complete`, `set-pr`) work without modification because the state file format is the same; only `init` and `generate_chore_steps` need changes
- `populate-phases` and `phase-count` are not used for chore chains (FR-3), so no changes to those commands

#### Implementation Steps
1. Add `generate_chore_steps` function to `scripts/workflow-state.sh` that produces the 9-step JSON array per FR-1:
   - Step 0: `{"name":"Document chore","skill":"documenting-chores","context":"main","status":"pending","artifact":null,"completedAt":null}`
   - Step 1: `{"name":"Review requirements (standard)","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null}`
   - Step 2: `{"name":"Document QA test plan","skill":"documenting-qa","context":"main","status":"pending","artifact":null,"completedAt":null}`
   - Step 3: `{"name":"Reconcile test plan","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null}`
   - Step 4: `{"name":"Execute chore","skill":"executing-chores","context":"fork","status":"pending","artifact":null,"completedAt":null}`
   - Step 5: `{"name":"PR review","skill":null,"context":"pause","status":"pending","artifact":null,"completedAt":null}`
   - Step 6: `{"name":"Reconcile post-review","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null}`
   - Step 7: `{"name":"Execute QA","skill":"executing-qa","context":"main","status":"pending","artifact":null,"completedAt":null}`
   - Step 8: `{"name":"Finalize","skill":"finalizing-workflow","context":"fork","status":"pending","artifact":null,"completedAt":null}`
2. Update the `cmd_init` function's `case` statement: replace the `chore` branch (currently `echo "Error: Chain type 'chore' is not yet implemented."`) with `steps=$(generate_chore_steps)` so it falls through to the normal state file creation logic
3. Keep the `bug` branch as "not yet implemented" (out of scope for FEAT-010)
4. Add unit tests to `scripts/__tests__/workflow-state.test.ts`:
   - `generate_chore_steps` produces exactly 9 steps with correct names, skills, and contexts
   - `init CHORE-001 chore` creates a valid state file with `type: "chore"`, `currentStep: 0`, `status: "in-progress"`, and 9 steps
   - All existing state commands (`status`, `advance`, `pause`, `resume`, `fail`, `complete`, `set-pr`) work with chore chain state files (same format, no chore-specific logic)
   - Idempotency: `init CHORE-001 chore` on an existing state file returns current state
   - Chain type detection: IDs with `CHORE-` prefix pass `validate_id`
5. Run `npm test -- --testPathPatterns=workflow-state` to verify all tests pass (existing + new)

#### Deliverables
- [x] Updated `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` -- `generate_chore_steps` function and `chore` case in `cmd_init`
- [x] Updated `scripts/__tests__/workflow-state.test.ts` -- chore chain unit tests

---

### Phase 2: SKILL.md -- Chore Chain Documentation and Procedures
**Feature:** [FEAT-010](../features/FEAT-010-orchestrate-chore-workflow-chain.md) | [#90](https://github.com/lwndev/lwndev-marketplace/issues/90)
**Status:** ✅ Complete
**Depends on:** Phase 1 (SKILL.md references `scripts/workflow-state.sh init {ID} chore` and the 9-step sequence)

#### Rationale
- The core deliverable -- adds chore chain awareness to the orchestration instructions Claude follows
- Must come after Phase 1 because the SKILL.md procedures call `init {ID} chore` and reference the 9-step state
- The feature chain documentation already establishes patterns (fork, main-context, pause, resume); chore chain documentation follows the same patterns with fewer steps and no phase loop

#### Implementation Steps
1. Add a **Chore Chain Step Sequence** section to SKILL.md (parallel to the existing "Feature Chain Step Sequence"), with the 9-step table from FR-1:
   | # | Step | Skill | Context |
   |---|------|-------|---------|
   | 1 | Document chore | `documenting-chores` | **main** |
   | 2 | Review requirements (standard) | `reviewing-requirements` | fork |
   | 3 | Document QA test plan | `documenting-qa` | **main** |
   | 4 | Reconcile test plan | `reviewing-requirements` | fork |
   | 5 | Execute chore | `executing-chores` | fork |
   | 6 | **PAUSE: PR review** | -- | pause |
   | 7 | Reconcile post-review | `reviewing-requirements` | fork |
   | 8 | Execute QA | `executing-qa` | **main** |
   | 9 | Finalize | `finalizing-workflow` | fork |
2. Add a **New Chore Workflow Procedure** section (parallel to "New Workflow Procedure") covering:
   - Step 1 runs `documenting-chores` in main context (may prompt user interactively)
   - Read the allocated `CHORE-NNN` ID from the artifact filename at `requirements/chores/CHORE-{ID}-*.md`
   - Call `scripts/workflow-state.sh init {ID} chore`
   - Write `.sdlc/workflows/.active`
   - Advance step 1 and continue
3. Update the **Arguments** section to document that `CHORE-NNN` IDs trigger chore chain resume, and that new chore workflows begin when step 1 of `documenting-chores` assigns the ID
4. Update the **Resume Procedure** to handle chore chain state: no `plan-approval` pause to handle; only `pr-review` pause exists (step 6)
5. Add chore-specific **Step Execution** instructions:
   - **Step 1 -- `documenting-chores` (main context)**: Run directly, read artifact from `requirements/chores/CHORE-{ID}-*.md`
   - **Step 3 -- `documenting-qa` (main context)**: Same pattern as feature chain step 5
   - **Step 5 -- `executing-chores` (fork)**: Fork via Agent tool; after completion, extract PR number from output or detect via `gh pr list --head {branch} --json number`; call `set-pr {ID} {pr-number} {branch}` (FR-4)
   - **Step 6 -- PR review pause**: Call `advance`, then `pause {ID} pr-review`; on resume, check `gh pr view` status (FR-7)
   - **Step 8 -- `executing-qa` (main context)**: Same pattern as feature chain step 6+N+4
   - Steps 2, 4, 7, 9 follow the existing fork pattern without chore-specific overrides
6. Add the chore chain to the **Relationship to Other Skills** section:
   ```
   Chore chain:
   documenting-chores -> reviewing-requirements (standard) -> documenting-qa
     -> reviewing-requirements (test-plan) -> executing-chores
     -> PAUSE -> reviewing-requirements (code-review) -> executing-qa -> finalizing-workflow
   ```
7. Update the **Verification Checklist** to include chore-specific checks (no plan-approval pause, no phase loop, PR extracted from `executing-chores`)
8. Validate skill passes `npm run validate`

#### Deliverables
- [x] Updated `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` -- chore chain step sequence, new chore workflow procedure, chore step execution instructions, updated resume procedure, updated relationship section

---

### Phase 3: Integration Tests and Validation
**Feature:** [FEAT-010](../features/FEAT-010-orchestrate-chore-workflow-chain.md) | [#90](https://github.com/lwndev/lwndev-marketplace/issues/90)
**Status:** ✅ Complete
**Depends on:** Phase 1 (state script chore support), Phase 2 (SKILL.md chore documentation)

#### Rationale
- Integration tests exercise the full chore workflow lifecycle that Phases 1 and 2 enable
- Skill validation tests confirm the SKILL.md changes don't break existing validation and include chore chain sections
- Final phase validates everything works together before the feature is complete

#### Implementation Steps
1. Add chore chain integration tests to `scripts/__tests__/orchestrating-workflows.test.ts`:
   - **Full lifecycle**: `init CHORE-001 chore` -> advance through all 9 steps -> `pause` at step 5 -> `resume` -> advance remaining -> `complete`
   - **PR metadata**: `set-pr CHORE-001 55 chore/CHORE-001-test` records metadata accessible via `status`
   - **No phase loop**: Verify `populate-phases` is not needed; state file has exactly 9 steps from init (no dynamic insertion)
   - **No plan-approval pause**: Verify chore chain has only `pr-review` pause; `pause CHORE-001 plan-approval` works at the API level but the step sequence has no plan-approval pause step
   - **Error recovery**: `fail` at step 4 (`executing-chores`) -> `resume` -> retry -> advance succeeds
   - **Stop hook**: Verify exit 2 for in-progress chore chain, exit 0 for paused/complete chore chain
2. Add SKILL.md validation tests for chore chain content:
   - SKILL.md contains "Chore Chain Step Sequence" section
   - SKILL.md contains "New Chore Workflow Procedure" or equivalent section
   - SKILL.md references `documenting-chores` and `executing-chores` sub-skills
   - SKILL.md documents chore chain in "Relationship to Other Skills" section
3. Verify all existing tests still pass (feature chain tests, stop hook tests, state script tests)
4. Run `npm run validate` to confirm skill validation passes
5. Run `npm test` to confirm all tests pass

#### Deliverables
- [x] Updated `scripts/__tests__/orchestrating-workflows.test.ts` -- chore chain integration tests and SKILL.md validation
- [x] Updated `scripts/__tests__/workflow-state.test.ts` -- chore chain unit tests (fully covered in Phase 1)

---

## Testing Strategy

### Unit Tests (Phase 1)
- **Framework:** vitest, executing bash via `child_process.execSync`
- **Isolation:** Temporary `.sdlc/workflows/` directory per test, cleaned up in `afterEach`
- **Coverage:** `generate_chore_steps` produces 9 steps with correct structure; `init CHORE-XXX chore` creates valid state; all state commands work with chore state files; idempotency on existing chore workflow

### Integration Tests (Phase 3)
- **Framework:** vitest
- **Coverage:** Full chore workflow lifecycle (init through complete), stop hook behavior with chore chains, PR metadata recording, error recovery, no phase loop or plan-approval pause
- **Approach:** Call state script commands in sequence to simulate orchestrator behavior; verify state file contents after each transition

### Skill Validation Tests (Phase 3)
- **Framework:** vitest with `ai-skills-manager` `validate()` API
- **Coverage:** SKILL.md contains chore chain sections, references chore sub-skills, passes structural validation
- **Pattern:** Extends existing tests in `orchestrating-workflows.test.ts`

### Manual Testing
- Full chore chain end-to-end with a real chore task
- Resume from PR-review pause point (step 6)
- Verify `documenting-qa` and `executing-qa` function correctly in main context for chore chains
- Verify sub-skills work standalone after orchestrator changes
- Verify stop hook blocks stop during in-progress chore chain

## Dependencies and Prerequisites

### Existing Dependencies (verified)
- FEAT-009 infrastructure in place: `workflow-state.sh` (10 commands), `stop-hook.sh`, `SKILL.md` with feature chain orchestration
- All 6 chore chain sub-skills exist under `plugins/lwndev-sdlc/skills/`: `documenting-chores`, `reviewing-requirements`, `documenting-qa`, `executing-chores`, `executing-qa`, `finalizing-workflow`
- `.sdlc/` is gitignored
- `qa/test-plans/` and `qa/test-results/` directories exist
- vitest test infrastructure in place with existing workflow state and orchestrating-workflows test files

### External Dependencies
- `jq` -- JSON manipulation in state scripts (checked at runtime)
- `gh` CLI -- PR status checks during resume
- Bash-compatible shell -- macOS/Linux native; Windows via WSL or Git Bash

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| SKILL.md grows too large with chore chain additions | Medium | Medium | Keep chore chain procedures concise; reuse existing fork/main-context/pause patterns by reference rather than duplicating |
| PR extraction from `executing-chores` output unreliable | Medium | Medium | Primary: parse subagent output for PR number. Fallback: detect via `gh pr list --head {branch} --json number`. Both paths documented in SKILL.md |
| Existing feature chain tests break from SKILL.md changes | Low | Low | Phase 3 re-runs all existing tests; SKILL.md changes are additive (new sections), not modifications to existing feature chain sections |
| Stop hook does not handle chore chains correctly | Low | Low | Stop hook reads state file generically (checks `status` and `currentStep`); chore state files use the same format as feature state files (NFR-2) |
| State script changes break existing feature chain workflows | Low | Low | Only `cmd_init` is modified (new `chore` case); the `feature` case is untouched; `generate_chore_steps` is a new function with no side effects on existing code |

## Success Criteria

- [ ] `scripts/workflow-state.sh init CHORE-XXX chore` initializes a 9-step chore chain state file with `type: "chore"`
- [ ] All 9 steps have correct names, skills, and context values matching FR-1
- [ ] All existing state commands (`status`, `advance`, `pause`, `resume`, `fail`, `complete`, `set-pr`) work with chore chain state files
- [ ] `populate-phases` and `phase-count` are not invoked for chore chains (no phase loop)
- [ ] Orchestrator SKILL.md includes chore chain step sequence table, new workflow procedure, and step execution instructions
- [ ] SKILL.md documents PR extraction from `executing-chores` output with `gh pr list` fallback
- [ ] Resume procedure handles chore chain state correctly (only `pr-review` pause, no `plan-approval`)
- [ ] Stop hook correctly blocks stop for in-progress chore chains and allows for paused/complete
- [ ] Sub-skills are NOT modified -- no `context: fork` added to their frontmatter (NFR-1)
- [ ] All unit and integration tests pass via `npm test`
- [ ] Skill validates via `npm run validate`
- [ ] Existing feature chain tests continue to pass

## Code Organization

```
plugins/lwndev-sdlc/skills/orchestrating-workflows/
├── SKILL.md                          # Phase 2: Add chore chain sections
└── scripts/
    ├── workflow-state.sh             # Phase 1: Add generate_chore_steps, enable chore in init
    └── stop-hook.sh                  # No changes needed (generic state file handling)

scripts/__tests__/
├── workflow-state.test.ts            # Phase 1: Add chore chain unit tests
└── orchestrating-workflows.test.ts   # Phase 3: Add chore chain integration + validation tests
```
