# QA Test Plan: SKILL.md Body Path Resolution

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-BUG-005 |
| **Requirement Type** | BUG |
| **Requirement ID** | BUG-005 |
| **Source Documents** | `requirements/bugs/BUG-005-skill-body-path-resolution.md` |
| **Date Created** | 2026-03-29 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/orchestrating-workflows.test.ts` | SKILL.md frontmatter validation, `${CLAUDE_PLUGIN_ROOT}` in stop hook, script existence checks, workflow-state.sh integration tests | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| Verify no bare `scripts/workflow-state.sh` references remain in SKILL.md body (outside frontmatter) | `scripts/__tests__/orchestrating-workflows.test.ts` | AC-4, RC-1 | High | PASS |
| Verify all body references use `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` | `scripts/__tests__/orchestrating-workflows.test.ts` | AC-1, AC-2, RC-1, RC-2 | High | PASS |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| No existing test validates that SKILL.md body content uses `${CLAUDE_SKILL_DIR}` for script references | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (body, lines 104-359) | RC-1, AC-4 | Write unit test matching the BUG-004 pattern (line 49 tests frontmatter; new test covers body) |
| No test distinguishes `${CLAUDE_SKILL_DIR}` (body) from `${CLAUDE_PLUGIN_ROOT}` (frontmatter) | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | RC-2, AC-2 | Write unit test asserting body references use `${CLAUDE_SKILL_DIR}` specifically |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| RC-1 | All 29 bare `scripts/workflow-state.sh` references must be prefixed with `${CLAUDE_SKILL_DIR}/` | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` body (lines 104-359) | Grep for bare `scripts/workflow-state.sh` in body content (outside frontmatter); expect 0 matches. Grep for `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh`; expect 29 matches. | PASS |
| RC-2 | Body content must use `${CLAUDE_SKILL_DIR}`, not `${CLAUDE_PLUGIN_ROOT}`, for script references | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` body | Grep for `${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh` in body; expect 0 matches. Confirm `${CLAUDE_PLUGIN_ROOT}` only appears in frontmatter stop hook (line 10). | PASS |

## Verification Checklist

| # | Criterion | Requirement Ref | Verification Method | Status |
|---|-----------|-----------------|-------------------|--------|
| 1 | All 29 occurrences of `scripts/workflow-state.sh` in the SKILL.md body are prefixed with `${CLAUDE_SKILL_DIR}/`, with no bare references remaining | AC-1, RC-1 | Grep body content for bare `scripts/workflow-state.sh` (not preceded by `${CLAUDE_SKILL_DIR}/`); expect 0 matches | PASS |
| 2 | `${CLAUDE_SKILL_DIR}` is used (not `${CLAUDE_PLUGIN_ROOT}`) for body content references | AC-2, RC-2 | Grep for `CLAUDE_PLUGIN_ROOT` in body content referencing `workflow-state.sh`; expect 0 matches | PASS |
| 3 | Workflow state commands execute successfully from any user working directory | AC-3, RC-1, RC-2 | Existing integration tests in `orchestrating-workflows.test.ts` exercise workflow-state.sh from a temp directory; all must pass | PASS |
| 4 | A test verifies no bare `scripts/workflow-state.sh` references remain in the SKILL.md body | AC-4, RC-1 | Confirm new test exists in `scripts/__tests__/orchestrating-workflows.test.ts` and passes | PASS |

## Deliverable Verification

| Deliverable | Source | Expected Path | Status |
|-------------|--------|---------------|--------|
| Fixed SKILL.md with all body paths prefixed | RC-1, RC-2 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | PASS |
| Regression test for body path references | AC-4 | `scripts/__tests__/orchestrating-workflows.test.ts` | PASS |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
