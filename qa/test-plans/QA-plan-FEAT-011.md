# QA Test Plan: Orchestrate Bug Fix Workflow Chain

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-FEAT-011 |
| **Requirement Type** | FEAT |
| **Requirement ID** | FEAT-011 |
| **Source Documents** | [FEAT-011-orchestrate-bug-fix-workflow-chain.md](../../requirements/features/FEAT-011-orchestrate-bug-fix-workflow-chain.md), [FEAT-011 Implementation Plan](../../requirements/implementation/FEAT-011-orchestrate-bug-fix-workflow-chain.md) |
| **Date Created** | 2026-03-29 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/workflow-state.test.ts` | Feature, chore, and bug chain state script unit tests (init, advance, pause, resume, fail, complete, set-pr, phase-count, populate-phases, phase-status, error handling) | PASS |
| `scripts/__tests__/orchestrating-workflows.test.ts` | Feature, chore, and bug chain skill validation (SKILL.md frontmatter, sections, sub-skill references), integration tests (lifecycle, error recovery, phase loop, stop hook, PR metadata, chore/bug chain lifecycle) | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| `generate_bug_steps` produces exactly 9 steps with correct names, skills, and contexts | `scripts/__tests__/workflow-state.test.ts` | FR-1, FR-5 | High | PASS |
| `init BUG-001 bug` creates valid state file with `type: "bug"`, `currentStep: 0`, 9 steps | `scripts/__tests__/workflow-state.test.ts` | FR-5, NFR-2 | High | PASS |
| All existing state commands work with bug chain state files (same format) | `scripts/__tests__/workflow-state.test.ts` | NFR-2 | High | PASS |
| Idempotency: `init BUG-001 bug` on existing state returns current state | `scripts/__tests__/workflow-state.test.ts` | NFR-3 | Medium | PASS |
| Chain type detection: `BUG-` prefix passes `validate_id` | `scripts/__tests__/workflow-state.test.ts` | FR-5 | Medium | PASS |
| Full bug lifecycle: init → advance through 9 steps → pause at step 6 (zero-indexed: 5) → resume → complete | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-1, FR-7 | High | PASS |
| PR metadata: `set-pr BUG-001 77 fix/BUG-001-test` records correctly | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-4 | High | PASS |
| No phase loop: bug state has exactly 9 steps from init, no `populate-phases` needed | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-3 | High | PASS |
| No plan-approval pause: bug step sequence has only `pr-review` pause | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-2 | High | PASS |
| Error recovery: `fail` at step 5 (zero-indexed: 4, `executing-bug-fixes`) → `resume` → retry → advance succeeds | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-1 | Medium | PASS |
| Stop hook: exit 2 for in-progress bug chain, exit 0 for paused/complete | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-9 | High | PASS |
| SKILL.md contains bug chain step sequence section | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-8 | High | PASS |
| SKILL.md references `documenting-bugs` and `executing-bug-fixes` | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-8 | Medium | PASS |
| SKILL.md documents bug chain in relationship section | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-8 | Medium | PASS |
| Existing feature and chore chain tests unchanged and passing | `scripts/__tests__/workflow-state.test.ts`, `scripts/__tests__/orchestrating-workflows.test.ts` | NFR-2 | Medium | PASS |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| PR extraction from `executing-bug-fixes` output or `gh pr list` fallback | Orchestrator SKILL.md procedure | FR-4 | Manual verify — this is orchestrator behavior (SKILL.md instructions), not testable code |
| Bug chain context strategy (main vs fork assignment per step) | Orchestrator SKILL.md procedure | FR-6 | Manual verify — validate SKILL.md step execution instructions assign correct contexts |
| Resume procedure with bug chain (no plan-approval handling) | Orchestrator SKILL.md procedure | FR-7, FR-8 | Manual verify — validate SKILL.md resume procedure documents bug-specific behavior |
| Sub-skill isolation (no `context: fork` in frontmatter) | Sub-skill SKILL.md files | NFR-1 | Code review — verify no sub-skill SKILL.md files were modified |
| Resume at PR-review pause when PR is closed | Orchestrator SKILL.md resume procedure | FR-7, Edge case 4 | Manual verify — resume should report PR state, suggest re-open or restart from step 5 |
| RC-N traceability through the chain | Orchestrator SKILL.md + sub-skills | FR-10 | Manual verify — RC-N handling is delegated to sub-skills; verify SKILL.md documents this delegation |
| New root causes discovered during execution | Orchestrator SKILL.md + `executing-bug-fixes` | Edge case 7 | Manual verify — validate that the orchestrator does not intervene; `executing-bug-fixes` handles internally |
| Branch naming (`fix/BUG-XXX-description`) and commit format (`fix(category): message`) | `executing-bug-fixes` sub-skill | Edge cases 5, 6 | Out of scope for orchestrator — handled entirely by `executing-bug-fixes` sub-skill |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| FR-1 | Bug chain 9-step sequence | `workflow-state.sh:generate_bug_steps` — 9 JSON objects with correct names/skills/contexts | Automated test | PASS |
| FR-2 | No plan-approval pause | `generate_bug_steps` output — no step with `context: "pause"` and `name` containing "Plan approval" | Automated test | PASS |
| FR-3 | No phase loop | Bug state file has exactly 9 steps from `init`; `populate-phases` not needed | Automated test | PASS |
| FR-4 | PR extracted from executing-bug-fixes | SKILL.md step 5 instructions — extract PR number from output or detect via `gh pr list`; call `set-pr` | Code review + manual verify | PASS |
| FR-5 | `generate_bug_steps` function and `bug` case in `cmd_init` | `workflow-state.sh:cmd_init` — `bug` case calls `generate_bug_steps` instead of error | Automated test | PASS |
| FR-6 | Context strategy (main: 1,3,8; fork: 2,4,5,7,9; pause: 6) | `generate_bug_steps` — step context fields; SKILL.md step execution procedures | Automated test + code review | PASS |
| FR-7 | PR review pause at step 6 | `workflow-state.sh` — `pause BUG-XXX pr-review` sets correct state; resume checks `gh pr view` | Automated test (state script) + manual verify (resume logic) | PASS |
| FR-8 | SKILL.md bug chain documentation | SKILL.md — new sections: bug step sequence, new bug workflow procedure, bug step execution, updated resume, bug verification checklist, bug relationship table | Automated test (section existence) + code review (content) | PASS |
| FR-9 | Stop hook handles bug chains | `stop-hook.sh` — reads state generically; bug state file uses same format | Automated test | PASS |
| FR-10 | RC-N traceability through chain | Orchestrator delegates RC-N handling to sub-skills; no orchestrator-level RC-N logic | Code review + manual verify | PASS |
| NFR-1 | Sub-skill isolation | Sub-skill SKILL.md files — no `context: fork` in frontmatter | Code review | PASS |
| NFR-2 | State file consistency | `init BUG-XXX bug` — produces JSON with same fields as feature/chore state | Automated test | PASS |
| NFR-3 | Idempotency | `init` on existing bug workflow returns current state | Automated test | PASS |
| AC-1 | `init BUG-XXX bug` initializes 9-step chain | `workflow-state.sh:cmd_init` with `bug` type | Automated test | PASS |
| AC-2 | Steps 2,4,5,7,9 forked; 1,3,8 main | `generate_bug_steps` context fields; SKILL.md procedures | Automated test + code review | PASS |
| AC-3 | Sub-skills NOT modified | Sub-skill SKILL.md files unchanged | Code review | PASS |
| AC-4 | PR review pause/resume with `lastResumedAt` | `pause`/`resume` commands on bug state file | Automated test | PASS |
| AC-5 | State records `type: "bug"` | `init BUG-XXX bug` output | Automated test | PASS |
| AC-6 | RC-N traceability maintained through full chain | Sub-skills handle RC-N internally; orchestrator delegates | Code review + manual verify | PASS |
| AC-7 | `reviewing-requirements` in correct modes | SKILL.md procedures — standard (step 2), test-plan reconciliation (step 4), code-review reconciliation (step 7) | Code review | PASS |
| AC-8 | Stop hook handles bug chain | `stop-hook.sh` with bug `.active` file | Automated test | PASS |
| AC-9 | `documenting-qa` and `executing-qa` in main context | `generate_bug_steps` context fields; SKILL.md procedures | Automated test + code review | PASS |
| AC-10 | No plan-approval pause | `generate_bug_steps` output — no plan-approval step | Automated test | PASS |
| AC-11 | No phase loop invoked | Bug init produces 9 fixed steps; SKILL.md has no phase loop for bugs | Automated test + code review | PASS |
| AC-12 | PR number extracted from `executing-bug-fixes` or `gh pr list` | SKILL.md step 5 fork instructions | Code review + manual verify | PASS |
| AC-13 | SKILL.md includes bug chain documentation | SKILL.md section presence | Automated test | PASS |

## Deliverable Verification

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| Updated `workflow-state.sh` with `generate_bug_steps` and `bug` case | Phase 1 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` | PASS |
| Bug chain unit tests | Phase 1 | `scripts/__tests__/workflow-state.test.ts` | PASS |
| Updated SKILL.md with bug chain sections | Phase 2 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | PASS |
| Bug chain integration tests and SKILL.md validation tests | Phase 3 | `scripts/__tests__/orchestrating-workflows.test.ts` | PASS |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
