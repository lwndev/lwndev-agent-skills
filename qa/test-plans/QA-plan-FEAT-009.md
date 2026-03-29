# QA Test Plan: Orchestrating Workflows Skill

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-FEAT-009 |
| **Requirement Type** | FEAT |
| **Requirement ID** | FEAT-009 |
| **Source Documents** | [FEAT-009-orchestrating-workflows-skill.md](../../requirements/features/FEAT-009-orchestrating-workflows-skill.md), [Implementation Plan](../../requirements/implementation/FEAT-009-orchestrating-workflows-skill.md) |
| **Date Created** | 2026-03-29 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/build.test.ts` | Validates all plugins and skills; hardcodes skill count as 11 — must update to 12 after adding `orchestrating-workflows` | PENDING |
| `scripts/__tests__/skill-utils.test.ts` | Tests `getSourcePlugins()` and `getSourceSkills()` — new skill must be discovered | PENDING |
| `scripts/__tests__/scaffold.test.ts` | Skill scaffolding — should remain unaffected | PENDING |
| `scripts/__tests__/implementing-plan-phases.test.ts` | Tests implementing-plan-phases skill validation — must still pass unmodified (NFR-3) | PENDING |
| `scripts/__tests__/executing-qa.test.ts` | Tests executing-qa skill validation — must still pass unmodified | PENDING |
| `scripts/__tests__/documenting-qa.test.ts` | Tests documenting-qa skill validation — must still pass unmodified | PENDING |
| `scripts/__tests__/reviewing-requirements.test.ts` | Tests reviewing-requirements skill validation — must still pass unmodified | PENDING |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| State script `init` creates valid JSON state file for feature type | `orchestrating-workflows/scripts/workflow-state.sh` | FR-1, AC-2 | High | -- |
| State script `init` creates valid state for chore and bug types | `orchestrating-workflows/scripts/workflow-state.sh` | AC-2, #90, #91 | High | -- |
| State script `init` is idempotent — returns existing state if file exists | `orchestrating-workflows/scripts/workflow-state.sh` | NFR-4, Edge Case 1 | High | -- |
| State script `init` rejects malformed IDs (lowercase, missing dash, wrong prefix) | `orchestrating-workflows/scripts/workflow-state.sh` | Edge Case 10 | Medium | -- |
| State script `status` validates required JSON fields on load | `orchestrating-workflows/scripts/workflow-state.sh` | NFR-5, AC-2 | High | -- |
| State script `status` errors on malformed/corrupted state file | `orchestrating-workflows/scripts/workflow-state.sh` | NFR-5, Edge Case 7 | Medium | -- |
| State script `advance` marks step complete and increments currentStep | `orchestrating-workflows/scripts/workflow-state.sh` | AC-2 | High | -- |
| State script `advance` is idempotent on completed step | `orchestrating-workflows/scripts/workflow-state.sh` | NFR-4 | Medium | -- |
| State script `advance` records artifact path when provided | `orchestrating-workflows/scripts/workflow-state.sh` | AC-2 | Medium | -- |
| State script `pause` sets status and pauseReason correctly | `orchestrating-workflows/scripts/workflow-state.sh` | FR-5, FR-6, AC-2 | High | -- |
| State script `resume` clears pauseReason and updates lastResumedAt | `orchestrating-workflows/scripts/workflow-state.sh` | FR-7, AC-2 | High | -- |
| State script `fail` records error message | `orchestrating-workflows/scripts/workflow-state.sh` | NFR-2, AC-2 | High | -- |
| State script `complete` marks workflow as complete | `orchestrating-workflows/scripts/workflow-state.sh` | AC-2 | Medium | -- |
| State script `set-pr` records prNumber and branch | `orchestrating-workflows/scripts/workflow-state.sh` | FR-9, AC-2 | Medium | -- |
| State script `phase-count` reads implementation plan and counts phases | `orchestrating-workflows/scripts/workflow-state.sh` | FR-4, AC-7 | High | -- |
| State script `phase-count` populates phase steps and post-phase steps in state | `orchestrating-workflows/scripts/workflow-state.sh` | FR-4, AC-7 | High | -- |
| State script `phase-status` returns per-phase completion info | `orchestrating-workflows/scripts/workflow-state.sh` | AC-2 | Medium | -- |
| SKILL.md passes plugin validation (`npm run validate`) | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | AC-1 | High | -- |
| Stop hook script exits 0 when workflow is paused | `orchestrating-workflows/scripts/workflow-stop-hook.sh` | AC-13 | High | -- |
| Stop hook script exits 0 when workflow is complete | `orchestrating-workflows/scripts/workflow-stop-hook.sh` | AC-13 | High | -- |
| Stop hook script exits 2 when workflow is in-progress with remaining steps | `orchestrating-workflows/scripts/workflow-stop-hook.sh` | AC-13 | High | -- |
| Stop hook script exits 0 when no active workflow file exists | `orchestrating-workflows/scripts/workflow-stop-hook.sh` | AC-13 | Medium | -- |
| Stop hook script exits 0 when workflow is failed | `orchestrating-workflows/scripts/workflow-stop-hook.sh` | AC-13 | Medium | -- |
| State script `phase-count` errors with clear message when plan has 0 phases | `orchestrating-workflows/scripts/workflow-state.sh` | FR-4, Edge Case 2 | Medium | -- |
| Concurrent workflows: `advance` on FEAT-001 does not alter FEAT-002 state | `orchestrating-workflows/scripts/workflow-state.sh` | Edge Case 9 | Medium | -- |
| Build test skill count updated from 11 to 12 | `scripts/__tests__/build.test.ts` | AC-1 | High | -- |
| Scripts bundled in skill directory, not project root | `orchestrating-workflows/scripts/` | AC-2 | High | -- |
| State script uses CWD for project paths (`.sdlc/`, `requirements/`) | `orchestrating-workflows/scripts/workflow-state.sh` | AC-2 | High | -- |
| Old scripts removed from project-root `scripts/` | `scripts/workflow-state.sh`, `scripts/workflow-stop-hook.sh` | AC-2 | Medium | -- |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| Forking mechanism (Agent tool delegation with SKILL.md content) | SKILL.md orchestration procedure | FR-3, AC-4, AC-5 | Manual verify — requires live Claude Code session to test Agent tool forking |
| Main context step execution (steps 1, 5, 6+N+4) | SKILL.md orchestration procedure | FR-2, AC-4 | Manual verify — confirm documenting-features, documenting-qa, executing-qa run inline |
| Phase loop with dynamic phase count | SKILL.md orchestration procedure | FR-4, AC-7, AC-8 | Manual verify — run orchestrator with a multi-phase implementation plan |
| Plan approval pause/resume cycle | SKILL.md orchestration procedure | FR-5, AC-10, AC-11 | Manual verify — pause at step 4, re-invoke with ID, confirm resume |
| PR review pause/resume with `gh pr view` status check | SKILL.md orchestration procedure | FR-6, AC-10, AC-12 | Manual verify — pause at PR review, re-invoke, verify status check |
| PR suppression during orchestrated phase execution | SKILL.md orchestration procedure | FR-10, AC-16 | Manual verify — confirm implementing-plan-phases skips PR creation when orchestrated |
| ID allocation delegation from step-1 sub-skill | SKILL.md orchestration procedure | FR-11 | Manual verify — confirm orchestrator reads ID from step-1 artifact |
| Reconciliation steps cannot be skipped | SKILL.md orchestration procedure | FR-8, AC-15 | Code review — verify step sequence in SKILL.md includes all reconciliation steps |
| Sub-skills unmodified after implementation | All existing skill SKILL.md files | NFR-3, AC-6 | Automated — `git diff` on existing skill directories must show no changes |
| `.sdlc/` gitignored | `.gitignore` | AC-3 | Automated — verify `.sdlc/` entry in `.gitignore` |
| State files written to correct location | `.sdlc/workflows/{ID}.json` | AC-3 | Automated — run `init` and check file exists at expected path |
| Active workflow tracking (`.sdlc/workflows/.active`) | `scripts/workflow-stop-hook.sh`, SKILL.md | AC-13 | Manual verify — confirm `.active` file is written on invocation and read by hook |
| Error handling: step failure halts chain | SKILL.md orchestration procedure | NFR-2, AC-14 | Manual verify — inject a failure and confirm chain halts with clear error |
| Edge case: PR already exists for branch | SKILL.md orchestration procedure | Edge Case 4 | Manual verify — test with pre-existing PR |
| Edge case: GitHub API unavailable during PR check | SKILL.md orchestration procedure | Edge Case 5 | Manual verify — test with network disconnected or invalid token |
| Edge case: Sub-skill SKILL.md not found | SKILL.md orchestration procedure | Edge Case 6 | Manual verify — rename a skill temporarily, confirm clear error |
| Edge case: Phase branch already exists — orchestrator continues committing | SKILL.md orchestration procedure | Edge Case 3 | Manual verify — create feature branch before running phase loop, confirm no failure |
| Edge case: Sub-skill invoked standalone does not corrupt orchestrator state | `.sdlc/workflows/{ID}.json`, existing skills | Edge Case 8 | Automated — run standalone `/reviewing-requirements` while state file exists, verify state unchanged |
| Edge case: Concurrent workflows — per-ID state isolation | `.sdlc/workflows/` | Edge Case 9 | Automated — create two state files, advance one, verify other unchanged |
| Scripts resolve project paths from CWD, not script location | `orchestrating-workflows/scripts/workflow-state.sh` | AC-2 | Automated — invoke script from project root, verify `.sdlc/` created relative to CWD not script dir |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| FR-1 | Feature chain step sequence (6 + N + 5 steps) | `scripts/workflow-state.sh init {ID} feature` populates correct step sequence; SKILL.md executes steps in order | Automated (state script) + Manual (orchestrator) | -- |
| FR-2 | Context strategy — main vs fork vs pause | SKILL.md: steps 1, 5, 6+N+4 run inline; others forked via Agent tool; steps 4, 6+N+2 pause | Manual — observe execution context per step | -- |
| FR-3 | Forking via Agent tool — read SKILL.md, spawn subagent | SKILL.md: Read tool reads `${CLAUDE_PLUGIN_ROOT}/skills/{name}/SKILL.md`, Agent tool spawns subagent | Manual — verify subagent receives correct prompt | -- |
| FR-4 | Phase loop — dynamic phase count, sequential execution | `scripts/workflow-state.sh phase-count {ID}` counts phases; SKILL.md loops through each | Automated (phase-count) + Manual (loop execution) | -- |
| FR-5 | Pause — plan approval at step 4 | `scripts/workflow-state.sh pause {ID} plan-approval`; SKILL.md displays message and halts | Automated (pause command) + Manual (halt behavior) | -- |
| FR-6 | Pause — PR review at step 6+N+2 with `gh pr view` check | `scripts/workflow-state.sh pause {ID} pr-review`; SKILL.md checks PR status on resume | Automated (pause command) + Manual (resume + PR check) | -- |
| FR-7 | Resume from state — paused, failed, in-progress | `scripts/workflow-state.sh status {ID}` + `resume {ID}`; SKILL.md handles each status | Automated (state commands) + Manual (resume paths) | -- |
| FR-8 | Reconciliation steps always included | SKILL.md step sequence includes reviewing-requirements at steps 2, 6, 6+N+3 | Code review — inspect SKILL.md step list | -- |
| FR-9 | PR creation step after all phases | SKILL.md forks subagent for `gh pr create`; `set-pr {ID} {pr-number} {branch}` | Manual — verify PR created and state updated | -- |
| FR-10 | PR suppression during orchestrated phases | SKILL.md appends "skip PR creation" to Agent task prompt for implementing-plan-phases | Manual — verify no PR created per-phase | -- |
| FR-11 | ID allocation delegated to step-1 sub-skill | SKILL.md reads ID from step-1 artifact filename after documenting-features completes | Manual — verify ID extracted from artifact | -- |
| NFR-1 | Context window efficiency via forking | Forked steps run in isolated Agent contexts | Manual — monitor context usage during multi-step chain | -- |
| NFR-2 | Error handling — step/phase/QA failures | `scripts/workflow-state.sh fail {ID} {message}`; SKILL.md halts and reports | Automated (fail command) + Manual (halt behavior) | -- |
| NFR-3 | Sub-skill isolation — no modifications | `git diff` on `plugins/lwndev-sdlc/skills/` (excluding `orchestrating-workflows/`) shows no changes | Automated — git diff check | -- |
| NFR-4 | Idempotency — advance/init no-ops on completed/existing | `scripts/workflow-state.sh advance` on completed step; `init` on existing ID | Automated — run commands twice, compare output | -- |
| NFR-5 | State file validation on load | `scripts/workflow-state.sh status {ID}` with corrupted JSON | Automated — provide malformed JSON and verify error | -- |
| AC-1 | Skill exists with frontmatter, description, Stop hook | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | Automated — `npm run validate` + manual inspect frontmatter | -- |
| AC-2 | State script handles all 10 commands | `orchestrating-workflows/scripts/workflow-state.sh` | Automated — invoke each command and verify output | -- |
| AC-3 | State files at `.sdlc/workflows/{ID}.json`; gitignored | `.gitignore`, `.sdlc/workflows/` | Automated — check gitignore entry + file creation path | -- |
| AC-4 | Steps 1, 5, 6+N+4 in main; others forked | SKILL.md procedure | Manual — observe context per step during execution | -- |
| AC-5 | Forked steps read SKILL.md and delegate as subagent prompts | SKILL.md forking mechanism | Manual — verify Agent tool receives SKILL.md content | -- |
| AC-6 | Sub-skills NOT modified | Existing skill directories | Automated — `git diff` shows no changes in existing skills | -- |
| AC-7 | Phase loop determines count from implementation plan | `phase-count` command + SKILL.md loop | Automated (phase-count) + Manual (loop execution) | -- |
| AC-8 | Each phase forks separately; same branch | SKILL.md phase loop | Manual — verify separate Agent calls, same git branch | -- |
| AC-9 | PR created only after final phase | SKILL.md post-phase PR step | Manual — verify no per-phase PRs, one PR after completion | -- |
| AC-10 | Pauses at step 4 and step 6+N+2 | SKILL.md pause logic + state script `pause` | Manual — verify halt at both points | -- |
| AC-11 | Resume reads state and continues correctly | SKILL.md resume logic + state script `resume` | Manual — re-invoke with ID, verify continuation | -- |
| AC-12 | PR review resume checks PR status via `gh pr view` | SKILL.md resume logic | Manual — verify `gh pr view` output parsed correctly | -- |
| AC-13 | Stop hook prevents premature stopping | `scripts/workflow-stop-hook.sh` + SKILL.md frontmatter | Automated (hook exit codes) + Manual (mid-chain stop attempt) | -- |
| AC-14 | Step failures halt chain with clear error | SKILL.md error handling + state script `fail` | Manual — inject failure, verify halt and error message | -- |
| AC-15 | Reconciliation steps cannot be skipped | SKILL.md step sequence | Code review — verify all 3 reconciliation steps present | -- |
| AC-16 | Orchestrated implementing-plan-phases skips PR | SKILL.md phase loop prompt override | Manual — verify no PR created during orchestrated phases | -- |

## Deliverable Verification

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| Updated `.gitignore` | Phase 1 | `.gitignore` (contains `.sdlc/` entry) | -- |
| State management script | Phase 1 → 4 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` (executable, 10 commands) | -- |
| Orchestrator skill | Phase 2 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | -- |
| Stop hook script | Phase 3 → 4 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-stop-hook.sh` (executable) | -- |
| Updated SKILL.md with Stop hook | Phase 3 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (frontmatter includes hooks.Stop) | -- |
| Active workflow tracking | Phase 3 | `.sdlc/workflows/.active` (written by orchestrator, read by hook) | -- |
| Updated build test skill count | Phase 2 | `scripts/__tests__/build.test.ts` (skill count = 12) | -- |
| Old scripts removed from project root | Phase 4 | `scripts/workflow-state.sh` and `scripts/workflow-stop-hook.sh` must NOT exist | -- |

> **Note:** The build test skill count update is not a formal phase deliverable — it is a regression fix implied by adding a new skill directory. It is also tracked in Existing Test Verification above.
>
> **Note:** Script paths in New Test Analysis and Coverage Gap Analysis use `orchestrating-workflows/scripts/` as shorthand for `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/`.

## Verification Checklist

Summary of all acceptance criteria with verification approach:

- [ ] **AC-1**: `orchestrating-workflows` skill exists — run `npm run validate`, inspect SKILL.md frontmatter for name, description, allowed-tools, hooks
- [ ] **AC-2**: `workflow-state.sh` (bundled in skill `scripts/` dir) handles all commands — invoke each of: `init`, `status`, `advance`, `pause`, `resume`, `fail`, `complete`, `set-pr`, `phase-count`, `phase-status` and verify JSON output; confirm scripts use CWD for project paths
- [ ] **AC-3**: State files at correct path and gitignored — run `init`, check `.sdlc/workflows/{ID}.json` exists, verify `.sdlc/` in `.gitignore`
- [ ] **AC-4**: Context strategy correct — manual: run orchestrator, observe steps 1/5/6+N+4 inline and others forked
- [ ] **AC-5**: Forking reads SKILL.md — manual: verify Agent tool prompt contains sub-skill SKILL.md content
- [ ] **AC-6**: Sub-skills unmodified — run `git diff plugins/lwndev-sdlc/skills/` excluding `orchestrating-workflows/`, confirm no changes
- [ ] **AC-7**: Phase loop dynamic count — run `phase-count` against an implementation plan, verify correct count and state population
- [ ] **AC-8**: Phases fork separately, same branch — manual: verify separate Agent invocations, `git log` shows all on same branch
- [ ] **AC-9**: PR after final phase only — manual: verify no PR during phase loop, one PR at step 6+N+1
- [ ] **AC-10**: Pauses at step 4 and 6+N+2 — manual: verify workflow halts at both points
- [ ] **AC-11**: Resume reads state correctly — manual: re-invoke with ID after pause, verify continuation from correct step
- [ ] **AC-12**: PR review checks status — manual: resume from PR review pause, verify `gh pr view` output parsed
- [ ] **AC-13**: Stop hook blocks mid-chain — test hook script exit codes: 0 for paused/complete/failed/no-active, 2 for in-progress
- [ ] **AC-14**: Failures halt chain — manual: inject failure, verify `fail` called and chain stops with error
- [ ] **AC-15**: Reconciliation mandatory — code review: verify SKILL.md step sequence includes all 3 reviewing-requirements invocations
- [ ] **AC-16**: PR suppression works — manual: verify implementing-plan-phases doesn't create PR when orchestrated

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
