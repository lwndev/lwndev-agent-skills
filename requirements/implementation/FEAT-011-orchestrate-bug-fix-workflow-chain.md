# Implementation Plan: Orchestrate Bug Fix Workflow Chain

## Overview

Add bug fix workflow chain support to the existing `orchestrating-workflows` skill. The bug chain is a 9-step fixed sequence (no phase loop, no plan-approval pause) with a single PR-review pause point, mirroring the chore chain structurally but using bug-specific skills (`documenting-bugs`, `executing-bug-fixes`). This builds entirely on the shared orchestration infrastructure from FEAT-009 and follows the pattern established by FEAT-010 for fixed 9-step chains. The work involves adding a `generate_bug_steps` function to the state script, replacing the "not yet implemented" guard for `bug` in `init`, and extending the SKILL.md with bug chain documentation and execution procedures.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-011 | [#91](https://github.com/lwndev/lwndev-marketplace/issues/91) | [FEAT-011-orchestrate-bug-fix-workflow-chain.md](../features/FEAT-011-orchestrate-bug-fix-workflow-chain.md) | High | Medium | Pending |

## Recommended Build Sequence

### Phase 1: State Script -- Bug Chain Support
**Feature:** [FEAT-011](../features/FEAT-011-orchestrate-bug-fix-workflow-chain.md) | [#91](https://github.com/lwndev/lwndev-marketplace/issues/91)
**Status:** ✅ Complete

#### Rationale
- Foundation that the SKILL.md procedures depend on -- `init BUG-XXX bug` must produce a valid 9-step state file before the orchestrator can reference it
- The state script currently returns "not yet implemented" for `bug`; this is the minimal change needed to unblock everything else
- Real code (bash + jq) that can be unit-tested independently before modifying the skill document
- All existing state commands (`status`, `advance`, `pause`, `resume`, `fail`, `complete`, `set-pr`) work without modification because the state file format is the same; only `init` and `generate_bug_steps` need changes
- `populate-phases` and `phase-count` are not used for bug chains (FR-3), so no changes to those commands
- Structurally identical to the chore chain addition in FEAT-010 Phase 1

#### Implementation Steps
1. Add `generate_bug_steps` function to `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` that produces the 9-step JSON array per FR-1:
   - Step 0: `{"name":"Document bug","skill":"documenting-bugs","context":"main","status":"pending","artifact":null,"completedAt":null}`
   - Step 1: `{"name":"Review requirements (standard)","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null}`
   - Step 2: `{"name":"Document QA test plan","skill":"documenting-qa","context":"main","status":"pending","artifact":null,"completedAt":null}`
   - Step 3: `{"name":"Reconcile test plan","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null}`
   - Step 4: `{"name":"Execute bug fix","skill":"executing-bug-fixes","context":"fork","status":"pending","artifact":null,"completedAt":null}`
   - Step 5: `{"name":"PR review","skill":null,"context":"pause","status":"pending","artifact":null,"completedAt":null}`
   - Step 6: `{"name":"Reconcile post-review","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null}`
   - Step 7: `{"name":"Execute QA","skill":"executing-qa","context":"main","status":"pending","artifact":null,"completedAt":null}`
   - Step 8: `{"name":"Finalize","skill":"finalizing-workflow","context":"fork","status":"pending","artifact":null,"completedAt":null}`
2. Update the `cmd_init` function's `case` statement: replace the `bug` branch (currently `echo "Error: Chain type 'bug' is not yet implemented."`) with `steps=$(generate_bug_steps)` so it falls through to the normal state file creation logic
3. Add unit tests to `scripts/__tests__/workflow-state.test.ts`:
   - `generate_bug_steps` produces exactly 9 steps with correct names, skills, and contexts
   - `init BUG-001 bug` creates a valid state file with `type: "bug"`, `currentStep: 0`, `status: "in-progress"`, and 9 steps
   - All existing state commands (`status`, `advance`, `pause`, `resume`, `fail`, `complete`, `set-pr`) work with bug chain state files (same format, no bug-specific logic)
   - Idempotency: `init BUG-001 bug` on an existing state file returns current state
   - Chain type detection: IDs with `BUG-` prefix pass `validate_id`
4. Run `npm test -- --testPathPatterns=workflow-state` to verify all tests pass (existing + new)

#### Deliverables
- [x] Updated `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` -- `generate_bug_steps` function and `bug` case in `cmd_init`
- [x] Updated `scripts/__tests__/workflow-state.test.ts` -- bug chain unit tests

---

### Phase 2: SKILL.md -- Bug Chain Documentation and Procedures
**Feature:** [FEAT-011](../features/FEAT-011-orchestrate-bug-fix-workflow-chain.md) | [#91](https://github.com/lwndev/lwndev-marketplace/issues/91)
**Status:** Pending
**Depends on:** Phase 1 (SKILL.md references `scripts/workflow-state.sh init {ID} bug` and the 9-step sequence)

#### Rationale
- The core deliverable -- adds bug chain awareness to the orchestration instructions Claude follows
- Must come after Phase 1 because the SKILL.md procedures call `init {ID} bug` and reference the 9-step state
- The feature and chore chain documentation already establish patterns (fork, main-context, pause, resume); bug chain documentation follows the same patterns as the chore chain with different sub-skills at steps 1 and 5

#### Implementation Steps
1. Add a **Bug Chain Step Sequence** section to SKILL.md (parallel to the existing "Chore Chain Step Sequence"), with the 9-step table from FR-1:
   | # | Step | Skill | Context |
   |---|------|-------|---------|
   | 1 | Document bug | `documenting-bugs` | **main** |
   | 2 | Review requirements (standard) | `reviewing-requirements` | fork |
   | 3 | Document QA test plan | `documenting-qa` | **main** |
   | 4 | Reconcile test plan | `reviewing-requirements` | fork |
   | 5 | Execute bug fix | `executing-bug-fixes` | fork |
   | 6 | **PAUSE: PR review** | -- | pause |
   | 7 | Reconcile post-review | `reviewing-requirements` | fork |
   | 8 | Execute QA | `executing-qa` | **main** |
   | 9 | Finalize | `finalizing-workflow` | fork |
2. Add a **New Bug Workflow Procedure** section (parallel to "New Chore Workflow Procedure") covering:
   - Step 1 runs `documenting-bugs` in main context (may prompt user interactively)
   - Read the allocated `BUG-NNN` ID from the artifact filename at `requirements/bugs/BUG-{ID}-*.md`
   - Call `scripts/workflow-state.sh init {ID} bug`
   - Write `.sdlc/workflows/.active`
   - Advance step 1 and continue
3. Update the **Arguments** section to document that `BUG-NNN` IDs trigger bug chain resume, and that new bug workflows begin when step 1 of `documenting-bugs` assigns the ID. Add keywords for detection: "bug", "fix", "defect", "regression"
4. Update the **Resume Procedure** to include bug chain: no `plan-approval` pause to handle; only `pr-review` pause exists (step 6) -- same as chore chain
5. Add bug-specific **Main-Context Steps** instructions:
   - **Step 1 -- `documenting-bugs` (main context)**: Run directly, read artifact from `requirements/bugs/BUG-{ID}-*.md`
   - **Step 3 -- `documenting-qa` (main context)**: Same pattern as chore chain step 3
   - **Step 8 -- `executing-qa` (main context)**: Same pattern as chore chain step 8
6. Add bug-specific **Step-Specific Fork Instructions**:
   - **Step 2 -- `reviewing-requirements` (standard review)**: Append `{ID}` as argument. Same as chore chain step 2
   - **Step 4 -- `reviewing-requirements` (test-plan reconciliation)**: Append `{ID}` as argument. Same as chore chain step 4
   - **Step 5 -- `executing-bug-fixes` (fork)**: Fork via Agent tool with `{ID}` as argument. After completion, extract PR number from output or detect via `gh pr list --head {branch} --json number`; call `set-pr {ID} {pr-number} {branch}` (FR-4). Branch pattern: `fix/BUG-XXX-description`
   - **Step 6 -- PR review pause**: Call `advance`, then `pause {ID} pr-review`; on resume, check `gh pr view` status (FR-7)
   - **Step 7 -- `reviewing-requirements` (code-review reconciliation)**: Append `{ID} --pr {prNumber}` as argument. Same as chore chain step 7
   - **Step 9 -- `finalizing-workflow`**: No special argument needed. Same as chore chain step 9
7. Add the bug chain to the **Relationship to Other Skills** section:
   ```
   Bug chain:
   documenting-bugs -> reviewing-requirements (standard) -> documenting-qa
     -> reviewing-requirements (test-plan) -> executing-bug-fixes
     -> PAUSE -> reviewing-requirements (code-review) -> executing-qa -> finalizing-workflow
   ```
   Add a **Bug Chain Skills** table parallel to the existing "Chore Chain Skills" table
8. Update the **Verification Checklist** to include bug-specific checks (no plan-approval pause, no phase loop, PR extracted from `executing-bug-fixes`, RC-N traceability maintained)
9. Validate skill passes `npm run validate`

#### Deliverables
- [ ] Updated `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` -- bug chain step sequence, new bug workflow procedure, bug step execution instructions, updated arguments and resume procedure, updated relationship section, updated verification checklist

---

### Phase 3: Integration Tests and Validation
**Feature:** [FEAT-011](../features/FEAT-011-orchestrate-bug-fix-workflow-chain.md) | [#91](https://github.com/lwndev/lwndev-marketplace/issues/91)
**Status:** Pending
**Depends on:** Phase 1 (state script bug support), Phase 2 (SKILL.md bug documentation)

#### Rationale
- Integration tests exercise the full bug workflow lifecycle that Phases 1 and 2 enable
- Skill validation tests confirm the SKILL.md changes don't break existing validation and include bug chain sections
- Final phase validates everything works together before the feature is complete

#### Implementation Steps
1. Add bug chain integration tests to `scripts/__tests__/orchestrating-workflows.test.ts`:
   - **Full lifecycle**: `init BUG-001 bug` -> advance through all 9 steps -> `pause` at step 5 -> `resume` -> advance remaining -> `complete`
   - **PR metadata**: `set-pr BUG-001 77 fix/BUG-001-test` records metadata accessible via `status`
   - **No phase loop**: Verify `populate-phases` is not needed; state file has exactly 9 steps from init (no dynamic insertion)
   - **No plan-approval pause**: Verify bug chain has only `pr-review` pause; the step sequence has no plan-approval pause step
   - **Error recovery**: `fail` at step 4 (`executing-bug-fixes`) -> `resume` -> retry -> advance succeeds
   - **Stop hook**: Verify exit 2 for in-progress bug chain, exit 0 for paused/complete bug chain
2. Add SKILL.md validation tests for bug chain content:
   - SKILL.md contains "Bug Chain Step Sequence" section
   - SKILL.md contains "New Bug Workflow Procedure" or equivalent section
   - SKILL.md references `documenting-bugs` and `executing-bug-fixes` sub-skills
   - SKILL.md documents bug chain in "Relationship to Other Skills" section
3. Verify all existing tests still pass (feature chain tests, chore chain tests, stop hook tests, state script tests)
4. Run `npm run validate` to confirm skill validation passes
5. Run `npm test` to confirm all tests pass

#### Deliverables
- [ ] Updated `scripts/__tests__/orchestrating-workflows.test.ts` -- bug chain integration tests and SKILL.md validation
- [ ] All existing tests continue to pass

---

## Testing Strategy

### Unit Tests (Phase 1)
- **Framework:** vitest, executing bash via `child_process.execSync`
- **Isolation:** Temporary `.sdlc/workflows/` directory per test, cleaned up in `afterEach`
- **Coverage:** `generate_bug_steps` produces 9 steps with correct structure; `init BUG-XXX bug` creates valid state; all state commands work with bug state files; idempotency on existing bug workflow

### Integration Tests (Phase 3)
- **Framework:** vitest
- **Coverage:** Full bug workflow lifecycle (init through complete), stop hook behavior with bug chains, PR metadata recording, error recovery, no phase loop or plan-approval pause
- **Approach:** Call state script commands in sequence to simulate orchestrator behavior; verify state file contents after each transition

### Skill Validation Tests (Phase 3)
- **Framework:** vitest with `ai-skills-manager` `validate()` API
- **Coverage:** SKILL.md contains bug chain sections, references bug sub-skills, passes structural validation
- **Pattern:** Extends existing tests in `orchestrating-workflows.test.ts`

### Manual Testing
- Full bug chain end-to-end with a real bug fix
- Resume from PR-review pause point (step 6)
- Verify `documenting-qa` and `executing-qa` function correctly in main context for bug chains
- Verify sub-skills work standalone after orchestrator changes
- Verify stop hook blocks stop during in-progress bug chain
- Verify RC-N traceability maintained through the full chain

## Dependencies and Prerequisites

### Existing Dependencies (verified)
- FEAT-009 infrastructure in place: `workflow-state.sh` (10 commands), `stop-hook.sh`, `SKILL.md` with feature chain orchestration
- FEAT-010 chore chain in place: `generate_chore_steps`, chore chain SKILL.md documentation, chore integration tests
- All 6 bug chain sub-skills exist under `plugins/lwndev-sdlc/skills/`: `documenting-bugs`, `reviewing-requirements`, `documenting-qa`, `executing-bug-fixes`, `executing-qa`, `finalizing-workflow`
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
| SKILL.md grows too large with bug chain additions | Medium | Medium | Keep bug chain procedures concise; reuse existing fork/main-context/pause patterns by reference rather than duplicating; bug chain mirrors chore chain structure so most documentation is parallel |
| PR extraction from `executing-bug-fixes` output unreliable | Medium | Medium | Primary: parse subagent output for PR number. Fallback: detect via `gh pr list --head {branch} --json number`. Both paths documented in SKILL.md. Same pattern proven in chore chain |
| Existing feature/chore chain tests break from SKILL.md changes | Low | Low | Phase 3 re-runs all existing tests; SKILL.md changes are additive (new sections), not modifications to existing chain sections |
| Stop hook does not handle bug chains correctly | Low | Low | Stop hook reads state file generically (checks `status` and `currentStep`); bug state files use the same format as feature/chore state files (NFR-2). Already verified with chore chains |
| State script changes break existing feature/chore workflows | Low | Low | Only `cmd_init` is modified (bug case replaces error stub); the `feature` and `chore` cases are untouched; `generate_bug_steps` is a new function with no side effects |

## Success Criteria

- [ ] `scripts/workflow-state.sh init BUG-XXX bug` initializes a 9-step bug chain state file with `type: "bug"`
- [ ] All 9 steps have correct names, skills, and context values matching FR-1
- [ ] All existing state commands (`status`, `advance`, `pause`, `resume`, `fail`, `complete`, `set-pr`) work with bug chain state files
- [ ] `populate-phases` and `phase-count` are not invoked for bug chains (no phase loop)
- [ ] Orchestrator SKILL.md includes bug chain step sequence table, new workflow procedure, and step execution instructions
- [ ] SKILL.md documents PR extraction from `executing-bug-fixes` output with `gh pr list` fallback
- [ ] Resume procedure handles bug chain state correctly (only `pr-review` pause, no `plan-approval`)
- [ ] Stop hook correctly blocks stop for in-progress bug chains and allows for paused/complete
- [ ] Sub-skills are NOT modified -- no `context: fork` added to their frontmatter (NFR-1)
- [ ] All unit and integration tests pass via `npm test`
- [ ] Skill validates via `npm run validate`
- [ ] Existing feature and chore chain tests continue to pass

## Code Organization

```
plugins/lwndev-sdlc/skills/orchestrating-workflows/
├── SKILL.md                          # Phase 2: Add bug chain sections
└── scripts/
    ├── workflow-state.sh             # Phase 1: Add generate_bug_steps, enable bug in init
    └── stop-hook.sh                  # No changes needed (generic state file handling)

scripts/__tests__/
├── workflow-state.test.ts            # Phase 1: Add bug chain unit tests
└── orchestrating-workflows.test.ts   # Phase 3: Add bug chain integration + validation tests
```
