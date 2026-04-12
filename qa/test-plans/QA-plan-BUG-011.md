# QA Test Plan: Stop Hook Findings Feedback Loop Fix

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-BUG-011 |
| **Requirement Type** | BUG |
| **Requirement ID** | BUG-011 |
| **Source Documents** | `requirements/bugs/BUG-011-stop-hook-findings-loop.md` |
| **Date Created** | 2026-04-12 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/workflow-state.test.ts` | Workflow state management tests (init, advance, pause, resume, fail, complete, set-pr, populate-phases, phase-count, set-complexity, model selection) | PASS |
| `scripts/__tests__/orchestrating-workflows.test.ts` | Orchestrating workflows skill structure, SKILL.md validation, stop-hook existence, reference files, model selection audit trail | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| `set-gate` subcommand sets `gate` field in state JSON | `scripts/workflow-state.sh` | RC-2, AC-1 | High | PASS |
| `clear-gate` subcommand removes `gate` field from state JSON | `scripts/workflow-state.sh` | RC-2, AC-4 | High | PASS |
| `set-gate` rejects invalid gate types | `scripts/workflow-state.sh` | RC-2, AC-1 | Medium | PASS |
| Stop hook exits 0 (allows stop) when state is in-progress with active gate | `scripts/stop-hook.sh` | RC-1, AC-2 | High | PASS |
| Stop hook exits 2 (blocks stop) when state is in-progress without gate | `scripts/stop-hook.sh` | RC-1, AC-5 | High | PASS |
| Stop hook exits 0 for paused state (plan-approval) unchanged | `scripts/stop-hook.sh` | AC-6 | Medium | PASS |
| Stop hook exits 0 for paused state (pr-review) unchanged | `scripts/stop-hook.sh` | AC-6 | Medium | PASS |
| Stop hook exits 0 for paused state (review-findings) unchanged | `scripts/stop-hook.sh` | AC-6 | Medium | PASS |
| Gate field survives state file round-trip (set → status → verify present) | `scripts/workflow-state.sh` | RC-2, AC-1 | Medium | PASS |
| SKILL.md documents gate set/clear instructions at findings decision points | `SKILL.md` | AC-3 | Medium | PASS |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| No existing tests for stop-hook.sh behavior (only existence check) | `scripts/stop-hook.sh` | RC-1 | Write integration tests that invoke stop-hook.sh with various state file configurations and verify exit codes |
| No existing tests for gate-related state fields | `scripts/workflow-state.sh` | RC-2 | Add unit tests for `set-gate` and `clear-gate` subcommands |
| No test covering stop hook + gate interaction | `scripts/stop-hook.sh` + `scripts/workflow-state.sh` | RC-1, RC-2 | Write integration test: set gate → run stop hook → verify exit 0 |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| RC-1 | Stop hook only inspects top-level status, unaware of sub-step gates | `stop-hook.sh:37-58` — `case "$STATUS"` block must add gate check before emitting nudge | Code review + automated test | PASS |
| RC-2 | State model lacks gate sub-state | `workflow-state.sh` — new `set-gate` / `clear-gate` subcommands must be added, writing `gate` field to state JSON | Code review + automated test | PASS |
| AC-1 | Gate mechanism exists in workflow state model | `workflow-state.sh` `set-gate` subcommand writes `"gate": "<type>"` to state JSON | Automated test | PASS |
| AC-2 | Stop hook suppresses nudge when gate is active | `stop-hook.sh` reads `gate` field from state JSON; if non-null, exits 0 | Automated test | PASS |
| AC-3 | Orchestrator sets gate before presenting findings decisions | `SKILL.md` Reviewing-Requirements Findings Handling section updated with gate-set instruction | Manual review | PASS |
| AC-4 | Orchestrator clears gate when user responds | `SKILL.md` Reviewing-Requirements Findings Handling section updated with gate-clear instruction | Manual review | PASS |
| AC-5 | Stop hook still nudges for in-progress without gate | `stop-hook.sh` existing `in-progress` branch continues to exit 2 when no gate is set | Automated test | PASS |
| AC-6 | Existing pause reasons work unchanged | `stop-hook.sh` `complete|paused` branch unmodified | Automated test | PASS |

## Deliverable Verification

| Deliverable | Source | Expected Path | Status |
|-------------|--------|---------------|--------|
| Updated stop-hook.sh with gate awareness | RC-1 fix, AC-5, AC-6 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/stop-hook.sh` | PASS |
| Updated workflow-state.sh with set-gate/clear-gate | RC-2 fix | `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` | PASS |
| Updated SKILL.md with gate instructions | AC-3, AC-4 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | PASS |
| New/updated tests for gate mechanism | All ACs | `scripts/__tests__/workflow-state.test.ts` and/or `scripts/__tests__/orchestrating-workflows.test.ts` | PASS |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
