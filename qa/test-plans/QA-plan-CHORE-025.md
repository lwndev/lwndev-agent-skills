# QA Test Plan: Align QA Templates with Execution Lifecycle

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-CHORE-025 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-025 |
| **Source Documents** | `requirements/chores/CHORE-025-align-qa-templates.md` |
| **Date Created** | 2026-03-28 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/documenting-qa.test.ts` — SKILL.md frontmatter (name, description) | Validates frontmatter has `name: documenting-qa` and non-empty description | PASS |
| `scripts/__tests__/documenting-qa.test.ts` — allowed-tools | Validates Read, Write, Edit, Glob, Grep, Agent present and Bash absent | PASS |
| `scripts/__tests__/documenting-qa.test.ts` — stop hook | Validates Stop hook with type: prompt, model: haiku, stop_hook_active | PASS |
| `scripts/__tests__/documenting-qa.test.ts` — template sections | Validates Metadata, Existing Test Verification, New Test Analysis, Coverage Gap Analysis, Code Path Verification sections exist | PASS |
| `scripts/__tests__/documenting-qa.test.ts` — template Plan Completeness Checklist | Updated to check `## Plan Completeness Checklist` (renamed from `## Verification Checklist`) | PASS |
| `scripts/__tests__/documenting-qa.test.ts` — SKILL.md sections | Validates When to Use, Verification Checklist, Relationship to Other Skills sections in SKILL.md | PASS |
| `scripts/__tests__/documenting-qa.test.ts` — validation API | Passes `ai-skills-manager` validation | PASS |
| `scripts/__tests__/executing-qa.test.ts` — SKILL.md frontmatter (name, description) | Validates frontmatter has `name: executing-qa` and non-empty description | PASS |
| `scripts/__tests__/executing-qa.test.ts` — allowed-tools | Validates Read, Write, Edit, Bash, Glob, Grep, Agent present | PASS |
| `scripts/__tests__/executing-qa.test.ts` — stop hook | Validates Stop hook with type: prompt, model: haiku, stop_hook_active | PASS |
| `scripts/__tests__/executing-qa.test.ts` — template sections | Validates Metadata, Test Suite Results, Per-Entry Verification Results, Issues Found and Fixed, Reconciliation Summary, Deviation Notes sections exist | PASS |
| `scripts/__tests__/executing-qa.test.ts` — SKILL.md sections | Validates When to Use, Verification Checklist, Relationship to Other Skills, Verification/Reconciliation loops, Preservation Rules | PASS |
| `scripts/__tests__/executing-qa.test.ts` — validation API | Passes `ai-skills-manager` validation | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| Update template Verification Checklist assertion to check for `## Plan Completeness Checklist` instead of `## Verification Checklist`. Note: AC1 applies only to the template heading, not the SKILL.md's own `## Verification Checklist` section (which is a standard skill structure element and remains unchanged). The test at line 34 (`skillMd.toContain('## Verification Checklist')`) should continue to pass as-is. | `scripts/__tests__/documenting-qa.test.ts` | AC1 | High | PASS |
| Add assertion that test plan template NTA table includes a `Status` column header | `scripts/__tests__/documenting-qa.test.ts` | AC3 | High | PASS |
| Add assertion that test plan template CPV table includes a `Status` column header | `scripts/__tests__/documenting-qa.test.ts` | AC3 | High | PASS |
| Add assertion that test plan template Deliverable table has `Status` column (not `Exists`) | `scripts/__tests__/documenting-qa.test.ts` | AC5 | High | PASS |
| Add assertion that test results template Per-Entry Verification Results section contains NTA-mirrored columns | `scripts/__tests__/executing-qa.test.ts` | AC4 | Medium | PASS |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| No test verifies that `documenting-qa` SKILL.md instructs checking off plan completeness items | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` | AC2 | Manual verify — SKILL.md is an LLM prompt, not executable code |
| No test verifies that `executing-qa` SKILL.md instructs writing back statuses to test plan | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | AC6 | Manual verify — SKILL.md is an LLM prompt, not executable code |

## Code Path Verification

Traceability from acceptance criteria to implementation:

| Requirement | Description | Expected Code Path | Verification Method |
|-------------|-------------|-------------------|-------------------|
| AC1 | Test plan template checklist renamed to "Plan Completeness Checklist" | `plugins/lwndev-sdlc/skills/documenting-qa/assets/test-plan-template.md` — `## Verification Checklist` section | Code review: section heading changed from `## Verification Checklist` to `## Plan Completeness Checklist` |
| AC2 | `documenting-qa` instructs checking off plan completeness items | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` — Step 3/Step 4 area | Code review: SKILL.md contains instruction to check off `- [x]` items in the Plan Completeness Checklist as the plan is built |
| AC3 | NTA, CPV, and Deliverable tables include `Status` column (default `--`) | `plugins/lwndev-sdlc/skills/documenting-qa/assets/test-plan-template.md` — NTA, CPV, Deliverable tables | Code review: each table header row includes `Status` and each data row includes `--` as default |
| AC4 | Per-Entry Verification Results restructured with NTA-mirrored columns | `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template.md` — `## Per-Entry Verification Results` | Code review: table columns mirror NTA structure with Result and Notes columns |
| AC5 | Deliverable table `Exists` column replaced by `Status` | `plugins/lwndev-sdlc/skills/documenting-qa/assets/test-plan-template.md` — Deliverable Verification table | Code review: column header is `Status` (not `Exists`), default value is `--` |
| AC6 | `executing-qa` updates Status columns during verification | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — Step 2 | Code review: SKILL.md instructs updating Existing Test `Status`, NTA `Status`, CPV `Status`, and Deliverable `Status` columns with PASS/FAIL/SKIP |
| AC7 | Existing tests updated to reflect template changes | `scripts/__tests__/documenting-qa.test.ts`, `scripts/__tests__/executing-qa.test.ts` | Automated test: assertions updated for renamed checklist and new Status columns |
| AC8 | All tests pass after changes | All test files | Automated test: `npm test` passes with zero failures |

## Deliverable Verification

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| Updated test plan template | Change A, B, AC5 | `plugins/lwndev-sdlc/skills/documenting-qa/assets/test-plan-template.md` | PASS |
| Updated documenting-qa SKILL.md | Change A | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` | PASS |
| Updated test results template | Change C | `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template.md` | PASS |
| Updated executing-qa SKILL.md | Change D | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | PASS |
| Updated documenting-qa tests | AC7 | `scripts/__tests__/documenting-qa.test.ts` | PASS |
| Updated executing-qa tests | AC7 | `scripts/__tests__/executing-qa.test.ts` | PASS |

## Scope Verification

Changes should be limited to the 6 affected files listed above. Verify no unrelated modifications are introduced:

| Scope Boundary | Verification |
|---------------|-------------|
| No changes to other skill SKILL.md files | Check git diff is scoped to the 6 listed files |
| No changes to build/scaffold scripts | Check `scripts/build.ts`, `scripts/scaffold.ts` are untouched |
| No changes to plugin.json | Check `.claude-plugin/plugin.json` is untouched |
| Template section structure preserved | Renamed/restructured sections retain their semantic role; no sections removed entirely |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All AC entries have corresponding test plan entries (AC1-AC8 mapped to Code Path Verification)
- [x] Coverage gaps are identified with recommendations (AC2, AC6 are prompt instructions — manual verify)
- [x] Code paths trace from requirements to implementation (all 8 ACs mapped)
- [x] Scope boundaries defined (6 affected files, no unrelated changes)
- [x] New test recommendations are actionable and prioritized (5 test updates identified)
