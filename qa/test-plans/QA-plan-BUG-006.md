# QA Test Plan: Missing Merge Strategy Flag

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-BUG-006 |
| **Requirement Type** | BUG |
| **Requirement ID** | BUG-006 |
| **Source Documents** | `requirements/bugs/BUG-006-merge-strategy-flag.md` |
| **Date Created** | 2026-03-29 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/build.test.ts` | Validates `finalizing-workflow` skill directory exists and passes plugin validation | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| No new automated tests — this is a SKILL.md content fix verified by code review | `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` | RC-1, RC-2 | High | PASS |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| SKILL.md content is a prompt document, not executable code — merge command correctness cannot be validated by automated tests | `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md:67` | RC-1, AC-1 | Manual verify via code review |
| Instructional text correctness is a prompt concern, not testable programmatically | `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md:70` | RC-2, AC-2 | Manual verify via code review |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| RC-1 | Merge command missing `--merge` flag | `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md:67` — command should read `gh pr merge --merge --delete-branch` | Code review | PASS |
| RC-2 | Instructional text tells agent to omit merge strategy flag | `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md:70` — text should explain why `--merge` is required instead of saying to omit it | Code review | PASS |

## Deliverable Verification

| Deliverable | Source | Expected Path | Status |
|-------------|--------|---------------|--------|
| Updated merge command with `--merge` flag | AC-1 (RC-1) | `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` line 67 | PASS |
| Updated instructional text | AC-2 (RC-2) | `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` line 70 | PASS |

## Verification Checklist

- [x] Merge command in SKILL.md includes `--merge` flag alongside `--delete-branch` (AC-1, RC-1)
- [x] Instructional text no longer tells the agent to omit the merge strategy flag (AC-2, RC-2)
- [x] Merge command would succeed on first attempt when executed non-interactively (AC-3, RC-1, RC-2)
- [x] Existing tests still pass (`npm test`) (regression baseline)
- [x] Plugin validation passes (`npm run validate`) (no structural regressions)

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
