# QA Test Plan: Apply Review Findings with Human Gate

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-CHORE-029 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-029 |
| **Source Documents** | `requirements/chores/CHORE-029-apply-review-findings-gate.md` |
| **Date Created** | 2026-03-29 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/workflow-state.test.ts` | All workflow-state.sh commands (init, advance, pause, resume, fail, complete, set-pr, populate-phases, phase-count) | PASS |
| `scripts/__tests__/orchestrating-workflows.test.ts` | SKILL.md structure validation (frontmatter, sections, `${CLAUDE_SKILL_DIR}` references) | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| `pause` command accepts `review-findings` as a valid reason | `scripts/__tests__/workflow-state.test.ts` | AC7 | High | PASS |
| `resume` from `review-findings` pause sets status to `in-progress` and clears pauseReason | `scripts/__tests__/workflow-state.test.ts` | AC7 | High | PASS |
| Existing `pause` tests still reject invalid reasons | `scripts/__tests__/workflow-state.test.ts` | AC7 (regression) | Medium | PASS |
| SKILL.md `${CLAUDE_SKILL_DIR}` reference count test must be updated to reflect new references added by findings-handling instructions | `scripts/__tests__/orchestrating-workflows.test.ts` | AC1 | Medium | PASS |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| Findings parsing logic lives in SKILL.md prose (not executable code) — cannot be unit tested | `orchestrating-workflows/SKILL.md` | AC1 | Manual verify: confirm SKILL.md instructions specify parsing the `Found **N errors**, **N warnings**, **N info**` summary line |
| Error-blocking behavior is orchestrator instruction, not code | `orchestrating-workflows/SKILL.md` | AC2 | Manual verify: confirm SKILL.md instructions block advancement when errors > 0 |
| Inline confirmation prompt behavior is instruction-driven | `orchestrating-workflows/SKILL.md` | AC3, AC6 | Manual verify: confirm SKILL.md instructions present findings and prompt user before advancing on warnings/info |
| Auto-fix and re-run loop is instruction-driven | `orchestrating-workflows/SKILL.md` | AC4, AC5 | Manual verify: confirm SKILL.md describes orchestrator applying fixes in main context and spawning a new review fork (max 1 re-run) |

## Code Path Verification

Traceability from acceptance criteria to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| AC1 | Orchestrator parses error/warning/info findings summary from each reviewing-requirements subagent (feature steps 2, 6, 6+N+3; chore steps 2, 4, 7) | `orchestrating-workflows/SKILL.md` — Forked Steps section and/or step-specific fork instructions for all reviewing-requirements invocations | Code review: verify parsing instructions exist for all 6 reviewing-requirements steps across both chains | PASS |
| AC2 | Errors block progression, surfaced to user | `orchestrating-workflows/SKILL.md` — findings-handling flow | Code review: verify instructions specify blocking advancement and displaying findings when error count > 0 | PASS |
| AC3 | Warnings/info presented with inline confirmation prompt before advancing | `orchestrating-workflows/SKILL.md` — findings-handling flow | Code review: verify instructions specify inline prompt with user confirmation for warnings/info | PASS |
| AC4 | Auto-fixable corrections applied when user opts in | `orchestrating-workflows/SKILL.md` — findings-handling flow | Code review: verify instructions describe offering auto-fixable items and applying them via Edit tool in main context | PASS |
| AC5 | Re-run review after fixes (max 1 re-run; pause on persistent errors) | `orchestrating-workflows/SKILL.md` — findings-handling flow | Code review: verify instructions spawn a new reviewing-requirements fork after fixes, cap at 1 re-run, and pause with `review-findings` if errors persist | PASS |
| AC6 | User can skip warnings and continue without fixes | `orchestrating-workflows/SKILL.md` — findings-handling flow | Code review: verify instructions offer skip/continue option for warnings | PASS |
| AC7 | Workflow state tracks review-gate pauses and resumes | `workflow-state.sh` — `cmd_pause` function | Automated test: `pause` accepts `review-findings`; `resume` clears it | PASS |

## Deliverable Verification

| Deliverable | Source | Expected Path | Status |
|-------------|--------|---------------|--------|
| Updated orchestrating-workflows SKILL.md with findings-handling instructions | CHORE-029 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | PASS |
| Updated workflow-state.sh with `review-findings` pause reason | CHORE-029 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` | PASS |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [ ] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
