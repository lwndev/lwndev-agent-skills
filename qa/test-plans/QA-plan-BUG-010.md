# QA Test Plan: QA Stop Hook Cross-Fire

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-BUG-010 |
| **Requirement Type** | BUG |
| **Requirement ID** | BUG-010 |
| **Source Documents** | `requirements/bugs/BUG-010-qa-stop-hook-cross-fire.md` |
| **Date Created** | 2026-04-12 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/documenting-qa.test.ts` — stop hook behavior | Tests that `documenting-qa` stop hook exits 0 on `stop_hook_active`, exits 0 on plan ref + completion indicator, exits 2 when missing, exits 0 on empty/malformed stdin | PASS |
| `scripts/__tests__/executing-qa.test.ts` — stop hook behavior | Tests that `executing-qa` stop hook exits 0 on `stop_hook_active`, exits 0 on verification + reconciliation, exits 2 when missing, exits 0 on empty/malformed stdin | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| `documenting-qa` hook exits 0 when `.sdlc/qa/.documenting-active` does not exist (no state file = skill not running) | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` | RC-1, AC-1 | High | PASS |
| `documenting-qa` hook exits 2 when `.sdlc/qa/.documenting-active` exists and keywords are absent | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` | RC-1, AC-5 | High | PASS |
| `documenting-qa` hook exits 0 when `.sdlc/qa/.documenting-active` exists and keywords are present | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` | RC-1, AC-5 | High | PASS |
| `documenting-qa` hook removes `.sdlc/qa/.documenting-active` on successful exit 0 (keyword match) | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` | RC-1, AC-8 | Medium | PASS |
| `executing-qa` hook exits 0 when `.sdlc/qa/.executing-active` does not exist | `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` | RC-2, AC-2 | High | PASS |
| `executing-qa` hook exits 2 when `.sdlc/qa/.executing-active` exists and keywords are absent | `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` | RC-2, AC-5 | High | PASS |
| `executing-qa` hook exits 0 when `.sdlc/qa/.executing-active` exists and keywords are present | `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` | RC-2, AC-5 | High | PASS |
| `executing-qa` hook removes `.sdlc/qa/.executing-active` on successful exit 0 (keyword match) | `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` | RC-2, AC-8 | Medium | PASS |
| `documenting-qa` SKILL.md contains state-file creation instruction (`mkdir -p .sdlc/qa && touch .sdlc/qa/.documenting-active`) | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` | RC-3, AC-3 | High | PASS |
| `executing-qa` SKILL.md contains state-file creation instruction (`mkdir -p .sdlc/qa && touch .sdlc/qa/.executing-active`) | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | RC-3, AC-4 | High | PASS |
| `documenting-qa` SKILL.md contains state-file removal instruction on completion | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` | RC-3, AC-3 | High | PASS |
| `executing-qa` SKILL.md contains state-file removal instruction on completion | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | RC-3, AC-4 | High | PASS |
| Existing `stop_hook_active` bypass still works for both hooks after gate is added | Both stop hook scripts | RC-1, RC-2 | Medium | PASS |
| Empty stdin and malformed JSON still exit 0 after gate is added | Both stop hook scripts | RC-1, RC-2 | Medium | PASS |
| Simulating `/releasing-plugins` context: both hooks exit 0 when no state files exist (cross-fire isolation) | Both stop hook scripts | RC-1, RC-2, AC-6 | Medium | PASS |
| Simulating `/executing-qa` context: `documenting-qa` hook exits 0 when `.sdlc/qa/.documenting-active` does not exist (cross-skill isolation) | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` | RC-1, AC-7 | Medium | PASS |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| No tests currently verify cross-fire isolation (hook behavior when other skills are active) | Both stop hook scripts | AC-6, AC-7 | Add integration-style tests that simulate unrelated skill execution (no state file present) |
| No tests verify state-file cleanup by hooks on successful completion | Both stop hook scripts | AC-8 | Add tests that create state file, run hook with matching keywords, verify state file is removed |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| RC-1 | `documenting-qa` stop hook lacks state-file gate | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` — new gate block before line 12 (before stdin read) | Automated test: run hook without `.sdlc/qa/.documenting-active`, verify exit 0 | PASS |
| RC-2 | `executing-qa` stop hook lacks state-file gate | `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` — new gate block before line 12 (before stdin read) | Automated test: run hook without `.sdlc/qa/.executing-active`, verify exit 0 | PASS |
| RC-3 | Neither SKILL.md manages state files | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` and `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — new instructions for state-file lifecycle | Code review: verify SKILL.md contains create-at-start and remove-on-completion instructions | PASS |

## Deliverable Verification

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| Updated `documenting-qa` stop hook with state-file gate | Bug fix | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` | PASS |
| Updated `executing-qa` stop hook with state-file gate | Bug fix | `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` | PASS |
| Updated `documenting-qa` SKILL.md with state-file instructions | Bug fix | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` | PASS |
| Updated `executing-qa` SKILL.md with state-file instructions | Bug fix | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | PASS |
| New/updated tests for state-file gate behavior | Bug fix | `scripts/__tests__/documenting-qa.test.ts`, `scripts/__tests__/executing-qa.test.ts` | PASS |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
