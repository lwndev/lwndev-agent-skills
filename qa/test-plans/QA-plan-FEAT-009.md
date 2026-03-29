# QA Test Plan: Orchestrating Workflows Skill

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-FEAT-009 |
| **Requirement Type** | FEAT |
| **Requirement ID** | FEAT-009 |
| **Source Documents** | [FEAT-009-orchestrating-workflows-skill.md](../../requirements/features/FEAT-009-orchestrating-workflows-skill.md), [FEAT-009 Implementation Plan](../../requirements/implementation/FEAT-009-orchestrating-workflows-skill.md) |
| **Date Created** | 2026-03-29 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/build.test.ts` | Validates entire plugin passes `npm run validate` — must still pass after adding `orchestrating-workflows` skill | PASS |
| `scripts/__tests__/skill-utils.test.ts` | Tests `getSourcePlugins()` and `getSourceSkills()` — must discover the new skill | PASS |
| `scripts/__tests__/argument-hint.test.ts` | Validates argument-hint frontmatter format across all skills — must pass for new skill's `argument-hint` | PASS |
| `scripts/__tests__/creating-implementation-plans.test.ts` | Validates `creating-implementation-plans` skill — regression for sub-skill invoked by orchestrator | PASS |
| `scripts/__tests__/documenting-features.test.ts` | Validates `documenting-features` skill — regression for sub-skill invoked by orchestrator | PASS |
| `scripts/__tests__/reviewing-requirements.test.ts` | Validates `reviewing-requirements` skill — regression for sub-skill invoked by orchestrator | PASS |
| `scripts/__tests__/documenting-qa.test.ts` | Validates `documenting-qa` skill — regression for sub-skill invoked by orchestrator | PASS |
| `scripts/__tests__/implementing-plan-phases.test.ts` | Validates `implementing-plan-phases` skill — regression for sub-skill invoked by orchestrator | PASS |
| `scripts/__tests__/executing-qa.test.ts` | Validates `executing-qa` skill — regression for sub-skill invoked by orchestrator | PASS |
| `scripts/__tests__/constants.test.ts` | Validates plugin/skill directory path helpers — must resolve new skill directory | PASS |
| _(no dedicated test file)_ | `finalizing-workflow` sub-skill has no dedicated test file; regression coverage provided by `build.test.ts` plugin-wide validation | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| State script `init` creates state file with correct step sequence | `scripts/workflow-state.sh` | FR-1, AC-2 | High | PASS |
| State script `init` returns current state for existing workflow (idempotent) | `scripts/workflow-state.sh` | NFR-4, AC-18 | High | PASS |
| State script `status` returns JSON with all required fields | `scripts/workflow-state.sh` | AC-2 | High | PASS |
| State script `status` validates JSON integrity and required fields | `scripts/workflow-state.sh` | NFR-5, AC-19 | High | PASS |
| State script `advance` marks step complete, increments currentStep | `scripts/workflow-state.sh` | AC-2 | High | PASS |
| State script `advance` records artifact path when provided | `scripts/workflow-state.sh` | AC-2 | Medium | PASS |
| State script `advance` is a no-op on completed step (idempotent) | `scripts/workflow-state.sh` | NFR-4, AC-18 | High | PASS |
| State script `pause` sets status and pauseReason | `scripts/workflow-state.sh` | AC-2, FR-5, FR-6 | High | PASS |
| State script `resume` clears pauseReason, clears error, sets lastResumedAt | `scripts/workflow-state.sh` | AC-2, FR-7 | High | PASS |
| State script `fail` records error message in state | `scripts/workflow-state.sh` | AC-2, NFR-2 | High | PASS |
| State script `complete` sets status to complete | `scripts/workflow-state.sh` | AC-2 | High | PASS |
| State script `set-pr` records PR number and branch | `scripts/workflow-state.sh` | AC-2, FR-9 | Medium | PASS |
| State script `phase-count` reads implementation plan and returns phase count | `scripts/workflow-state.sh` | FR-4, AC-7 | High | PASS |
| State script `phase-count` errors on 0 phases | `scripts/workflow-state.sh` | Edge Case 2 | Medium | PASS |
| State script `phase-status` returns per-phase completion | `scripts/workflow-state.sh` | AC-2 | Medium | PASS |
| State script checks for `jq` availability at entry | `scripts/workflow-state.sh` | Edge Case 12 | Medium | PASS |
| State script rejects malformed JSON state files | `scripts/workflow-state.sh` | NFR-5, AC-19 | High | PASS |
| State script `init` writes state file with correct JSON structure (all required fields: `id`, `type`, `currentStep`, `status`, `pauseReason`, `steps`, `phases`, `prNumber`, `branch`, `startedAt`, `lastResumedAt`) | `scripts/workflow-state.sh` | AC-2, AC-3 | High | PASS |
| PR review pause/resume cycle with mock `gh pr view` — covers approved, changes-requested, and pending-review outcomes | `scripts/workflow-state.sh`, `scripts/stop-hook.sh` | FR-6, AC-12 | Medium | PASS |
| SKILL.md has valid frontmatter (name, description, argument-hint, compatibility) | `SKILL.md` | AC-1 | High | PASS |
| SKILL.md passes `validate()` from `ai-skills-manager` | `SKILL.md` | AC-1 | High | PASS |
| SKILL.md has required sections (When to Use, Quick Start, Verification Checklist, Relationship to Other Skills) | `SKILL.md` | AC-1 | High | PASS |
| Stop hook exits 0 for paused workflows | `scripts/stop-hook.sh` | AC-13 | High | PASS |
| Stop hook exits 0 for complete workflows | `scripts/stop-hook.sh` | AC-13 | High | PASS |
| Stop hook exits 2 for in-progress workflows with step description | `scripts/stop-hook.sh` | AC-13 | High | PASS |
| Stop hook exits 0 when `.active` file missing or empty | `scripts/stop-hook.sh` | AC-13 | High | PASS |
| Stop hook cleans up stale `.active` file | `scripts/stop-hook.sh` | Edge Case 11 | Medium | PASS |
| Integration: init → advance → pause → resume → advance → complete lifecycle | `scripts/workflow-state.sh`, `scripts/stop-hook.sh` | FR-7, AC-11 | High | PASS |
| Integration: init → advance → fail → resume → retry lifecycle | `scripts/workflow-state.sh` | NFR-2, AC-14 | High | PASS |
| State script `populate-phases` inserts phase steps and post-phase steps | `scripts/workflow-state.sh` | FR-4, AC-7 | High | PASS |
| State script `populate-phases` sets phases.total | `scripts/workflow-state.sh` | FR-4 | Medium | PASS |
| State script `populate-phases` is idempotent | `scripts/workflow-state.sh` | NFR-4 | Medium | PASS |
| State script `resume` clears previous error on retry | `scripts/workflow-state.sh` | NFR-2, FR-7 | Medium | PASS |
| Integration: phase loop state transitions with dynamic phase count | `scripts/workflow-state.sh` | FR-4, AC-7, AC-8 | High | PASS |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| Context isolation — forked steps don't pollute orchestrator context | SKILL.md orchestration logic | FR-2, FR-3, NFR-1 | Manual verify: run full chain, confirm orchestrator retains minimal context after forked steps |
| Agent tool forking pattern reads correct SKILL.md | SKILL.md fork instructions | FR-3, AC-5 | Manual verify: inspect Agent tool invocations during orchestrated run |
| Main-context steps (1, 5, 6+N+4) run in orchestrator conversation | SKILL.md context strategy | FR-2, AC-4 | Manual verify: confirm documenting-features, documenting-qa, executing-qa run inline |
| PR suppression via prompt instruction to implementing-plan-phases | SKILL.md phase loop | FR-11, AC-16 | Manual verify: confirm no PR created per-phase during orchestrated run |
| Sub-skills work standalone after orchestrator addition | All sub-skill SKILL.md files | NFR-3, AC-6 | Manual verify: invoke each sub-skill directly, confirm no behavioral change |
| Reconciliation steps cannot be skipped from step sequence | SKILL.md step sequence | FR-8, AC-15 | Code review: verify SKILL.md step sequence includes all reconciliation steps |
| ID allocation read from step-1 artifact | SKILL.md new-workflow flow | FR-10, AC-17 | Manual verify: start new workflow, confirm ID comes from documenting-features output |
| Plan-approval pause displays correct message and resumes | SKILL.md pause logic | FR-5, AC-10 | Manual verify: trigger pause at step 4, confirm message, resume and confirm continuation |
| PR-review pause displays PR link and resumes correctly | SKILL.md resume logic | FR-6, AC-12 | Manual verify: trigger pause after PR, confirm display; automated mock test covers gh pr view outcomes (see New Test Analysis) |
| Chain detection from ID prefix | SKILL.md argument handling | FR-1 | Code review: verify SKILL.md handles FEAT-, CHORE-, BUG- prefixes |
| Unrecognized ID prefix produces error | SKILL.md argument handling | Edge Case 10 | Manual verify: invoke with invalid prefix |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| FR-1 | Feature chain step sequence (6+N+5 steps) | SKILL.md step sequence table; `workflow-state.sh init` generates matching steps | Code review + automated test | PASS |
| FR-2 | Context strategy (main, fork, pause) | SKILL.md instructions per step; steps 1/5/6+N+4 inline, others via Agent tool | Code review + manual verify | PASS |
| FR-3 | Forking via Agent tool | SKILL.md fork pattern: read SKILL.md → spawn Agent → validate artifact → advance | Code review + manual verify | PASS |
| FR-4 | Phase loop (steps 7…6+N) | SKILL.md phase loop; `workflow-state.sh phase-count` reads plan | Automated test (phase-count) + manual verify (loop) | PASS |
| FR-5 | Pause — plan approval | SKILL.md pause logic; `workflow-state.sh pause {ID} plan-approval` | Automated test (pause command) + manual verify (message/resume) | PASS |
| FR-6 | Pause — PR review | SKILL.md pause logic; `workflow-state.sh pause {ID} pr-review`; resume checks `gh pr view` | Automated test (pause command) + manual verify (gh status check) | PASS |
| FR-7 | Resume from state | SKILL.md resume logic; `workflow-state.sh resume {ID}` updates lastResumedAt | Automated test (resume command) + manual verify (step continuation) | PASS |
| FR-8 | Reconciliation steps always included | SKILL.md step sequence includes reviewing-requirements at steps 2, 6, 6+N+3 | Code review | PASS |
| FR-9 | PR creation step | SKILL.md PR step; `workflow-state.sh set-pr {ID} {number} {branch}` | Automated test (set-pr command) + manual verify (PR created) | PASS |
| FR-10 | ID allocation delegation | SKILL.md reads ID from step-1 artifact filename | Code review + manual verify | PASS |
| FR-11 | PR suppression for implementing-plan-phases | SKILL.md appends "skip PR" instruction to Agent prompt | Code review + manual verify | PASS |
| NFR-1 | Context window efficiency | Forked steps get clean context; orchestrator stays lightweight | Manual verify: monitor context usage during full chain | PASS |
| NFR-2 | Error handling (step/phase/QA failure) | `workflow-state.sh fail`; SKILL.md halt logic | Automated test (fail command) + manual verify (halt behavior) | PASS |
| NFR-3 | Sub-skill isolation | No modifications to sub-skill SKILL.md files | Code review: diff sub-skill files before/after; manual verify standalone invocation | PASS |
| NFR-4 | Idempotency | `workflow-state.sh advance` no-op on completed; `init` returns existing | Automated test | PASS |
| NFR-5 | State file validation | `workflow-state.sh status` validates JSON integrity and required fields | Automated test | PASS |

## Deliverable Verification

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| State management script | Phase 1 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` | PASS |
| State script unit tests | Phase 1 | `scripts/__tests__/workflow-state.test.ts` | PASS |
| Orchestration skill document | Phase 2 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | PASS |
| Stop hook script | Phase 3 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/stop-hook.sh` | PASS |
| Skill validation + integration tests | Phase 3 | `scripts/__tests__/orchestrating-workflows.test.ts` | PASS |

## Verification Checklist

Based on acceptance criteria from FEAT-009:

| AC # | Criterion | Verification Method | Status |
|------|-----------|-------------------|--------|
| AC-1 | `orchestrating-workflows` skill exists with frontmatter, description, and Stop hook | Automated test (validate API) + code review | PASS |
| AC-2 | `scripts/workflow-state.sh` handles all 10 commands | Automated test (unit tests for each command) | PASS |
| AC-3 | State files written to `.sdlc/workflows/{ID}.json`; `.sdlc/` is gitignored | Automated test (init creates file) + code review (.gitignore) | PASS |
| AC-4 | Step 1, documenting-qa, and executing-qa run in main context | Code review (SKILL.md) + manual verify | PASS |
| AC-5 | Forked steps read SKILL.md content and delegate as subagent task prompts | Code review (SKILL.md fork pattern) + manual verify | PASS |
| AC-6 | Sub-skills NOT modified — no `context: fork` added to frontmatter | Code review: diff all sub-skill SKILL.md files | PASS |
| AC-7 | Phase loop dynamically determines phase count from implementation plan | Automated test (phase-count command) | PASS |
| AC-8 | Each phase forks separately; all commit to same branch | Code review (SKILL.md) + manual verify | PASS |
| AC-9 | PR created only after final phase completes (not per-phase) | Code review (SKILL.md) + manual verify | PASS |
| AC-10 | Pauses at plan approval (step 4) and PR review (step 6+N+2) | Automated test (pause command) + manual verify | PASS |
| AC-11 | Resume via re-invocation reads state and continues from correct step | Automated test (resume + status) + manual verify | PASS |
| AC-12 | PR review resume checks actual PR status via `gh pr view` | Code review (SKILL.md) + manual verify | PASS |
| AC-13 | Stop hook prevents premature stopping mid-chain | Automated test (stop hook exit codes) | PASS |
| AC-14 | Step failures halt the chain with clear error reporting | Automated test (fail command) + code review (SKILL.md halt logic) | PASS |
| AC-15 | Reconciliation steps cannot be skipped or omitted from step sequence | Code review (SKILL.md step sequence) | PASS |
| AC-16 | When orchestrated, implementing-plan-phases does not create a PR | Code review (SKILL.md prompt instruction) + manual verify | PASS |
| AC-17 | Orchestrator reads allocated ID from step-1 artifact | Code review (SKILL.md) + manual verify | PASS |
| AC-18 | State script operations are idempotent | Automated test (advance no-op, init existing) | PASS |
| AC-19 | Malformed state files produce clear error with suggestion to restart | Automated test (malformed JSON input) | PASS |

## Edge Case Verification

| # | Edge Case | Verification Method | Status |
|---|-----------|-------------------|--------|
| 1 | Workflow already exists for ID — resume rather than re-init | Automated test (init idempotency) | PASS |
| 2 | Implementation plan has 0 phases — error with clear message | Automated test (phase-count with empty plan) | PASS |
| 3 | Phase branch already exists — continue committing | Manual verify | PASS |
| 4 | PR already exists for branch — detect and record | Manual verify | PASS |
| 5 | GitHub API unavailable during PR check — report error, stay paused | Manual verify | PASS |
| 6 | Sub-skill SKILL.md not found — error with clear message | Code review (SKILL.md error handling) | PASS |
| 7 | State file corrupted or malformed — error with restart suggestion | Automated test (malformed JSON) | PASS |
| 8 | User invokes sub-skill standalone mid-workflow — no conflict | Manual verify | PASS |
| 9 | Multiple concurrent workflows — per-ID isolation | Automated test (two concurrent state files) | PASS |
| 10 | Unrecognized or malformed ID prefix — error with supported prefixes | Manual verify | PASS |
| 11 | Stale `.active` file — hook cleans up and allows stop | Automated test (stop hook with stale file) | PASS |
| 12 | `jq` not installed — clear error and install instructions | Automated test (mock missing jq) | PASS |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
