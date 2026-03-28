# QA Test Plan: Update Workflow Chains

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-CHORE-026 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-026 |
| **Source Documents** | `requirements/chores/CHORE-026-update-workflow-chains.md` |
| **Date Created** | 2026-03-28 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/build.test.ts` | Validates SKILL.md exists in each skill directory and frontmatter parses correctly | PASS |
| `scripts/__tests__/skill-utils.test.ts` | Validates SKILL.md frontmatter parsing | PASS |
| `scripts/__tests__/scaffold.test.ts` | Scaffold creates valid skill structure | PASS |
| `scripts/__tests__/reviewing-requirements.test.ts` | Asserts `## Relationship to Other Skills` section exists in reviewing-requirements SKILL.md | PASS |
| `scripts/__tests__/documenting-qa.test.ts` | Asserts `## Relationship to Other Skills` section exists in documenting-qa SKILL.md | PASS |
| `scripts/__tests__/executing-qa.test.ts` | Asserts `## Relationship to Other Skills` section exists in executing-qa SKILL.md | PASS |
| `scripts/__tests__/documenting-features.test.ts` | Asserts `## Relationship to Other Skills` section exists in documenting-features SKILL.md | PASS |
| `scripts/__tests__/documenting-chores.test.ts` | Asserts `## Relationship to Other Skills` section exists in documenting-chores SKILL.md | PASS |
| `scripts/__tests__/documenting-bugs.test.ts` | Asserts `## Relationship to Other Skills` section exists in documenting-bugs SKILL.md | PASS |
| `scripts/__tests__/executing-chores.test.ts` | Asserts `## Relationship to Other Skills` section exists in executing-chores SKILL.md | PASS |
| `scripts/__tests__/executing-bug-fixes.test.ts` | Asserts `## Relationship to Other Skills` section exists in executing-bug-fixes SKILL.md | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority |
|-----------------|----------------|-----------------|----------|
| No new automated tests required — this is a documentation-only change | N/A | AC-9 | N/A |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| No automated validation of workflow chain content in SKILL.md sections | All 9 SKILL.md files | AC-1 through AC-8 | Manual verify via code review — this is documentation content not suited to automated testing |

## Code Path Verification

Traceability from acceptance criteria to implementation:

| Requirement | Description | Expected Code Path | Verification Method |
|-------------|-------------|-------------------|-------------------|
| AC-1 | All 9 skill SKILL.md files have "Relationship to Other Skills" updated | `plugins/lwndev-sdlc/skills/{9 skills}/SKILL.md` | Code review: grep for updated workflow chains in each file |
| AC-2 | Feature chain reorder: `documenting-qa` after `creating-implementation-plans` | Files containing the feature workflow chain: 9 SKILL.md files + `CLAUDE.md` + `plugins/lwndev-sdlc/README.md` | Code review: verify feature chain shows `creating-implementation-plans` → `documenting-qa` (not the reverse) in each file |
| AC-3 | Task tables include reconciliation review entries | 9 SKILL.md files with task tables | Code review: verify "test-plan reconciliation" and "code-review reconciliation" rows exist |
| AC-4 | Task tables include `finalizing-workflow` entry | 9 SKILL.md files with task tables | Code review: verify `finalizing-workflow` row in each task table |
| AC-5 | Prose descriptions updated for reconciliation steps and finalizing-workflow | SKILL.md files with prose workflow descriptions | Code review: verify "After documenting..." prose mentions reconciliation and finalizing |
| AC-6 | CLAUDE.md workflow chains updated | `CLAUDE.md` | Code review: verify three chains match updated format |
| AC-7 | Plugin README.md workflow chains updated | `plugins/lwndev-sdlc/README.md` | Code review: verify three chains match updated format |
| AC-8 | Reconciliation steps described as optional but recommended | All files referencing reconciliation | Code review: verify language uses "optional" / "recommended" phrasing |
| AC-9 | No functional changes to skill behavior | All modified files | Code review: confirm only documentation sections changed; run `npm test` and `npm run validate` |

## Deliverable Verification

| Deliverable | Source | Expected Path | Exists |
|-------------|--------|---------------|--------|
| Updated reviewing-requirements SKILL.md | AC-1 | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | PASS |
| Updated documenting-qa SKILL.md | AC-1 | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` | PASS |
| Updated executing-qa SKILL.md | AC-1 | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | PASS |
| Updated documenting-features SKILL.md | AC-1 | `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md` | PASS |
| Updated documenting-chores SKILL.md | AC-1 | `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md` | PASS |
| Updated documenting-bugs SKILL.md | AC-1 | `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md` | PASS |
| Updated executing-chores SKILL.md | AC-1 | `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` | PASS |
| Updated executing-bug-fixes SKILL.md | AC-1 | `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` | PASS |
| Updated finalizing-workflow SKILL.md | AC-1 | `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` | PASS |
| Updated plugin README.md | AC-7 | `plugins/lwndev-sdlc/README.md` | PASS |
| Updated CLAUDE.md | AC-6 | `CLAUDE.md` | PASS |

## Verification Checklist

- [ ] All existing tests pass (regression baseline)
- [ ] All AC entries have corresponding test plan entries
- [ ] Coverage gaps are identified with recommendations
- [ ] Code paths trace from requirements to implementation
- [ ] Phase deliverables are accounted for
- [ ] New test recommendations are actionable and prioritized
