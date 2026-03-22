# QA Test Plan: Acceptance Criteria Checkoff During Execution

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-CHORE-018 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-018 |
| **Source Documents** | `requirements/chores/CHORE-018-acceptance-criteria-checkoff.md` |
| **Date Created** | 2026-03-22 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/executing-chores.test.ts` | Validates executing-chores SKILL.md structure, frontmatter, allowed-tools, PR template, workflow, and ai-skills-manager validation | PENDING |
| `scripts/__tests__/executing-bug-fixes.test.ts` | Validates executing-bug-fixes SKILL.md structure, frontmatter, allowed-tools, PR template, workflow, and ai-skills-manager validation | PENDING |
| `scripts/__tests__/implementing-plan-phases.test.ts` | Validates implementing-plan-phases SKILL.md structure, frontmatter, allowed-tools, references, and ai-skills-manager validation | PENDING |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority |
|-----------------|----------------|-----------------|----------|
| `executing-chores` SKILL.md or workflow-details.md contains explicit instruction to check off acceptance criteria in source chore document | `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`, `plugins/lwndev-sdlc/skills/executing-chores/references/workflow-details.md` | AC-1 | High |
| `executing-bug-fixes` SKILL.md or workflow-details.md contains explicit instruction to check off acceptance criteria in source bug document | `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`, `plugins/lwndev-sdlc/skills/executing-bug-fixes/references/workflow-details.md` | AC-2 | High |
| `implementing-plan-phases` SKILL.md or step-details.md contains explicit instruction to check off deliverables as each is completed (not just at the end) | `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md`, `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` | AC-3 | High |
| All three skills use a consistent pattern (same edit syntax `- [ ]` to `- [x]`, similar placement in workflow) | All 6 affected files | AC-4 | High |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| No existing test verifies that `executing-chores` mentions checking off AC checkboxes in source documents | `scripts/__tests__/executing-chores.test.ts` | AC-1 | Add test: workflow or SKILL.md should contain instruction to update `- [ ]` to `- [x]` in chore document |
| No existing test verifies that `executing-bug-fixes` mentions checking off AC checkboxes in source documents | `scripts/__tests__/executing-bug-fixes.test.ts` | AC-2 | Add test: workflow or SKILL.md should contain instruction to update `- [ ]` to `- [x]` in bug document |
| No existing test verifies that `implementing-plan-phases` requires incremental deliverable checkoff | `scripts/__tests__/implementing-plan-phases.test.ts` | AC-3 | Add test: step-details.md or SKILL.md should contain instruction to check off deliverables as completed |
| No existing test verifies consistency of checkoff pattern across all three skills | None | AC-4 | Add cross-skill test or manual verification that all three use the same `- [ ]` to `- [x]` edit pattern |

## Code Path Verification

Traceability from acceptance criteria to implementation:

| Requirement | Description | Expected Code Path | Verification Method |
|-------------|-------------|-------------------|-------------------|
| AC-1 | `executing-chores` instructions require checking off each acceptance criterion in the chore document as it is verified | `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` (Quick Start or Workflow Checklist) and/or `plugins/lwndev-sdlc/skills/executing-chores/references/workflow-details.md` (Phase 2: Execution, Step 5) | Code review: verify explicit instruction exists to edit the source chore document's acceptance criteria from `- [ ]` to `- [x]` as each criterion is verified |
| AC-2 | `executing-bug-fixes` instructions require checking off each acceptance criterion in the bug document as it is verified | `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` (Quick Start or Workflow Checklist) and/or `plugins/lwndev-sdlc/skills/executing-bug-fixes/references/workflow-details.md` (Phase 2: Execution, Step 6) | Code review: verify explicit instruction exists to edit the source bug document's acceptance criteria from `- [ ]` to `- [x]` as each criterion is verified |
| AC-3 | `implementing-plan-phases` instructions require checking off each deliverable in the implementation plan as it is completed | `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` (Quick Start or Workflow) and/or `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` (Step 7: Execute Implementation) | Code review: verify explicit instruction exists to check off deliverables (`- [ ]` to `- [x]`) at the point each deliverable is completed, not only at the end in Step 10 |
| AC-4 | All three skills follow a consistent pattern for when and how checkboxes are updated | All 6 affected files | Code review: compare the checkoff instructions across all three skills — they should use the same edit syntax (`- [ ]` to `- [x]`), similar workflow placement (during execution, not batched at end), and consistent language |

## Deliverable Verification

| Deliverable | Source | Expected Path | Exists |
|-------------|--------|---------------|--------|
| Updated `executing-chores` SKILL.md with checkoff instructions | CHORE-018, AC-1 | `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` | YES (to be modified) |
| Updated `executing-chores` workflow-details.md with checkoff instructions | CHORE-018, AC-1 | `plugins/lwndev-sdlc/skills/executing-chores/references/workflow-details.md` | YES (to be modified) |
| Updated `executing-bug-fixes` SKILL.md with checkoff instructions | CHORE-018, AC-2 | `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` | YES (to be modified) |
| Updated `executing-bug-fixes` workflow-details.md with checkoff instructions | CHORE-018, AC-2 | `plugins/lwndev-sdlc/skills/executing-bug-fixes/references/workflow-details.md` | YES (to be modified) |
| Updated `implementing-plan-phases` SKILL.md with checkoff instructions | CHORE-018, AC-3 | `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` | YES (to be modified) |
| Updated `implementing-plan-phases` step-details.md with incremental checkoff instructions | CHORE-018, AC-3 | `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` | YES (to be modified) |

## Scope Verification

Changes should be limited to the 6 affected files listed above. Verify no unrelated files are modified:

| Scope Check | Expected Result | Verification Method |
|-------------|----------------|---------------------|
| Only skill instruction files are modified | No changes to test files, build scripts, or other skills | `git diff --stat` against main branch |
| No structural changes to skill directories | Directory structure unchanged; only file content updated | `git diff --name-only` shows only the 6 affected files |
| Existing skill behavior preserved | Skills still pass ai-skills-manager validation after changes | `npm run validate` and `npm test` |

## Verification Checklist

- [ ] All existing tests pass (regression baseline)
- [ ] All AC entries (AC-1 through AC-4) have corresponding test plan entries
- [ ] Coverage gaps are identified with recommendations
- [ ] Code paths trace from requirements to implementation
- [ ] Deliverables are accounted for
- [ ] New test recommendations are actionable and prioritized
