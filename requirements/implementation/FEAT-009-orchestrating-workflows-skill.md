# Implementation Plan: Orchestrating Workflows Skill

## Overview

Build the `orchestrating-workflows` skill that drives SDLC workflow chains (feature, chore, bug) end-to-end through a single invocation. The skill sequences sub-skill invocations, manages state across pause points, and isolates per-step context via Agent tool forking. The implementation is split into three phases: state management infrastructure (bash script), core skill logic (SKILL.md), and stop hook with integration testing.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-009 | [#89](https://github.com/lwndev/lwndev-marketplace/issues/89) | [FEAT-009-orchestrating-workflows-skill.md](../features/FEAT-009-orchestrating-workflows-skill.md) | High | High | ✅ Complete |

## Recommended Build Sequence

### Phase 1: State Management Script
**Feature:** [FEAT-009](../features/FEAT-009-orchestrating-workflows-skill.md) | [#89](https://github.com/lwndev/lwndev-marketplace/issues/89)
**Status:** ✅ Complete

#### Rationale
- Foundation that all other phases depend on — both the orchestration logic and stop hook call this script
- Real code (bash + jq) that can be tested independently before the skill document exists
- Validates the state file format and command interface before building the SKILL.md around them
- Establishes the `.sdlc/workflows/` directory structure used throughout the feature

#### Implementation Steps
1. Create the skill directory structure: `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/`
2. Implement `scripts/workflow-state.sh` with a `jq` availability check at script entry (edge case 12)
3. Implement `init {ID} {type}` — create `.sdlc/workflows/{ID}.json` with the feature chain step sequence from FR-1; if state file already exists, return current state (NFR-4 idempotency)
4. Implement `status {ID}` — read and return state file as JSON; validate JSON integrity and required fields (`id`, `type`, `status`, `steps`, `currentStep`) on load (NFR-5)
5. Implement `advance {ID} [artifact-path]` — mark current step complete with timestamp, record optional artifact path, increment `currentStep`; no-op if step already complete (NFR-4)
6. Implement `pause {ID} {reason}` — set `status: "paused"` and `pauseReason` (accepts `plan-approval` or `pr-review`)
7. Implement `resume {ID}` — set `status: "in-progress"`, clear `pauseReason`, set `lastResumedAt` to current ISO 8601 timestamp
8. Implement `fail {ID} {message}` — set `status: "failed"` with error message in state
9. Implement `complete {ID}` — set `status: "complete"`
10. Implement `set-pr {ID} {pr-number} {branch}` — record `prNumber` and `branch` in state
11. Implement `phase-count {ID}` — read the implementation plan at `requirements/implementation/FEAT-{ID}-*.md`, count `### Phase N:` headings, return the count
12. Implement `phase-status {ID}` — return per-phase completion status from state file's `steps` array (filter by `phaseNumber`)
13. Write vitest unit tests in `scripts/__tests__/workflow-state.test.ts` — execute bash commands via `child_process.execSync`, use a temporary `.sdlc/workflows/` directory for isolation; cover all 10 commands, idempotency, validation errors, and edge cases (0 phases, malformed JSON, missing `jq`)

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` — state management script with all 10 commands
- [x] `scripts/__tests__/workflow-state.test.ts` — unit tests for state script

---

### Phase 2: SKILL.md — Orchestration Logic
**Feature:** [FEAT-009](../features/FEAT-009-orchestrating-workflows-skill.md) | [#89](https://github.com/lwndev/lwndev-marketplace/issues/89)
**Status:** ✅ Complete
**Depends on:** Phase 1 (SKILL.md references `scripts/workflow-state.sh` throughout)

#### Rationale
- The core deliverable — the orchestration instructions that Claude follows when the skill is invoked
- Depends on Phase 1 because every step calls the state script to track progress
- Must be a single coherent document that covers the full workflow lifecycle: new, resume, pause, fork, error

#### Implementation Steps
1. Create `SKILL.md` with YAML frontmatter: `name: orchestrating-workflows`, `description`, `argument-hint: "<title-or-issue> or <ID>"`, `compatibility: "Requires jq and a bash-compatible shell"`
2. Write the "When to Use This Skill" section — single entry point for feature/chore/bug chains
3. Write argument handling: detect new workflow (free-text title or `#N` issue) vs resume (existing ID like `FEAT-003`); for new workflows, detect chain type from title context; for resume, detect chain type from ID prefix (FR-10)
4. Write the new-workflow flow:
   - Step 1 runs `documenting-features` in main context (may prompt user interactively)
   - Read the allocated ID from the step-1 artifact filename (FR-10)
   - Call `scripts/workflow-state.sh init {ID} feature` to create state
   - Write ID to `.sdlc/workflows/.active`
5. Write the fork pattern (FR-3): read sub-skill's SKILL.md from `${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/SKILL.md`, spawn general-purpose subagent via Agent tool with SKILL.md content as task prompt (appending work item ID), validate artifact on return, call `advance`
6. Write forked step instructions for: `reviewing-requirements` (standard, step 2), `creating-implementation-plans` (step 3), `reviewing-requirements` (test-plan reconciliation, step 6), `reviewing-requirements` (code-review reconciliation, step 6+N+3), `finalizing-workflow` (step 6+N+5)
7. Write main-context step instructions for: `documenting-qa` (step 5) and `executing-qa` (step 6+N+4) — these run directly in the orchestrator's conversation because they rely on Stop hooks that don't fire when forked (#92)
8. Write the phase loop (FR-4): call `phase-count` to determine N, dynamically describe steps 7…6+N, fork `implementing-plan-phases FEAT-{ID} {phase-number}` for each phase, halt on failure
9. Write the PR creation step (FR-9): fork a subagent to create the PR, call `set-pr` to record it. For FR-11 (PR suppression): instruct the implementing-plan-phases subagent to skip PR creation by appending explicit instructions to the Agent prompt (e.g., "Do NOT create a pull request at the end — the orchestrator handles PR creation separately"). This avoids modifying the sub-skill itself (NFR-3)
10. Write plan-approval pause (FR-5): after step 3, call `pause {ID} plan-approval`, display message, halt; on resume, confirm with user before advancing
11. Write PR-review pause (FR-6): after PR creation, call `pause {ID} pr-review`, display PR link; on resume, check `gh pr view` status — advance if approved, stay paused if changes requested or pending
12. Write resume logic (FR-7): read state file, determine current step, handle pause-specific resume (FR-5/FR-6), retry failed steps, continue in-progress steps; call `resume {ID}` on successful resume to update `lastResumedAt`
13. Write error handling: step failure → call `fail {ID} {message}`, display error, halt; phase failure → halt loop, don't proceed to PR; QA failure → `executing-qa` handles retries internally, orchestrator records if unfixable
14. Write the "Verification Checklist" and "Relationship to Other Skills" sections
15. Validate skill passes `npm run validate`

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — orchestration skill document

---

### Phase 3: Stop Hook and Integration Testing
**Feature:** [FEAT-009](../features/FEAT-009-orchestrating-workflows-skill.md) | [#89](https://github.com/lwndev/lwndev-marketplace/issues/89)
**Status:** ✅ Complete
**Depends on:** Phase 1 (stop hook calls `workflow-state.sh status`), Phase 2 (hook registered in SKILL.md frontmatter)

#### Rationale
- Stop hook depends on both the state script (Phase 1) and SKILL.md frontmatter registration (Phase 2)
- Integration tests exercise the full lifecycle that Phases 1 and 2 enable
- Final phase validates everything works together before the feature is complete

#### Implementation Steps
1. Create `scripts/stop-hook.sh`:
   - Read the active workflow ID from `.sdlc/workflows/.active`
   - If file doesn't exist or is empty → exit 0 (allow stop)
   - Call `scripts/workflow-state.sh status {ID}`
   - If workflow is `complete` or `paused` → exit 0 (allow stop)
   - If state file doesn't exist (stale `.active`) → clean up `.active`, exit 0 (edge case 11)
   - If workflow is `in-progress` → exit 2 with message "Continue to step N+1: {description}"
2. Register stop hook in SKILL.md frontmatter `hooks` field as a command hook on Stop
3. Write integration tests in `scripts/__tests__/orchestrating-workflows.test.ts`:
   - Full lifecycle: init → advance through multiple steps → pause → resume → complete
   - Stop hook behavior: returns exit 0 for paused/complete, exit 2 for in-progress
   - Stale `.active` file cleanup
   - Error recovery: fail → resume → retry
   - Phase loop state transitions with dynamic phase count
4. Write skill validation test in `scripts/__tests__/orchestrating-workflows.test.ts`:
   - SKILL.md has required frontmatter fields (name, description, argument-hint, compatibility)
   - SKILL.md has required sections (When to Use, Quick Start, Verification Checklist, Relationship to Other Skills)
   - Skill passes `validate()` from `ai-skills-manager`
5. Verify `npm run validate` and `npm test` pass

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/stop-hook.sh` — stop hook script
- [x] `scripts/__tests__/orchestrating-workflows.test.ts` — skill validation and integration tests

---

## Testing Strategy

### Unit Tests (Phase 1)
- **Framework:** vitest, executing bash via `child_process.execSync`
- **Isolation:** Temporary `.sdlc/workflows/` directory per test, cleaned up in `afterEach`
- **Coverage:** All 10 state script commands, idempotency (advance on completed step, init on existing workflow), validation (malformed JSON, missing fields), edge cases (0 phases, missing `jq`)

### Integration Tests (Phase 3)
- **Framework:** vitest
- **Coverage:** Full workflow lifecycle, stop hook behavior across all states, error recovery, phase loop transitions
- **Approach:** Call state script commands in sequence to simulate orchestrator behavior; verify state file contents after each transition

### Skill Validation Tests (Phase 3)
- **Framework:** vitest with `ai-skills-manager` `validate()` API
- **Coverage:** Frontmatter fields, required sections, SKILL.md structure
- **Pattern:** Follows existing skill tests (e.g., `executing-chores.test.ts`)

### Manual Testing
- Full feature chain end-to-end with a real feature
- Resume from each pause point (plan approval, PR review)
- Verify sub-skills work standalone after orchestrator is added
- Verify context isolation (forked steps don't pollute orchestrator context)

## Dependencies and Prerequisites

### Existing Dependencies (verified)
- All 7 sub-skills exist under `plugins/lwndev-sdlc/skills/`
- `.sdlc/` is gitignored
- `qa/test-plans/` and `qa/test-results/` directories exist
- vitest test infrastructure in place

### External Dependencies
- `jq` — JSON manipulation in state scripts (checked at runtime)
- `gh` CLI — PR status checks during resume
- Bash-compatible shell — macOS/Linux native; Windows via WSL or Git Bash

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| SKILL.md too large for context window | High | Medium | Keep orchestration instructions concise; delegate logic to state script; use references for detailed patterns |
| FR-11 PR suppression via prompt instruction unreliable | Medium | Medium | Append explicit "Do NOT create a PR" instruction to Agent prompt; verify in integration test; fall back to creating PR separately if skill ignores instruction |
| `jq` not available on user system | Medium | Low | Check at script entry; clear error with install instructions (edge case 12) |
| Sub-skill SKILL.md changes break forking assumptions | Low | Low | Forking reads SKILL.md as-is; sub-skills remain stable; no coupling beyond reading the file |
| State file corruption from concurrent access | Low | Low | State files are per-ID; concurrent workflows don't share files (edge case 9) |

## Success Criteria

- [ ] All 10 state script commands work correctly with idempotency and validation
- [ ] Skill validates via `npm run validate`
- [ ] Stop hook correctly blocks stop for in-progress workflows and allows for paused/complete
- [ ] All unit and integration tests pass via `npm test`
- [ ] Feature chain step sequence in SKILL.md matches FR-1 exactly
- [ ] Forked steps use Agent tool pattern without modifying sub-skills (NFR-3)
- [ ] Main-context steps (1, 5, 6+N+4) run directly in orchestrator conversation

## Code Organization

```
plugins/lwndev-sdlc/skills/orchestrating-workflows/
├── SKILL.md                          # Phase 2: Orchestration logic
└── scripts/
    ├── workflow-state.sh             # Phase 1: State management (10 commands)
    └── stop-hook.sh                  # Phase 3: Prevent premature stop

scripts/__tests__/
├── workflow-state.test.ts            # Phase 1: State script unit tests
└── orchestrating-workflows.test.ts   # Phase 3: Skill validation + integration tests
```
