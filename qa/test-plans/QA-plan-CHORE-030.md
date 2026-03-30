# QA Test Plan: Make Phase Commit-Push Mandatory

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-CHORE-030 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-030 |
| **Source Documents** | `requirements/chores/CHORE-030-phase-commit-push-mandatory.md` |
| **Date Created** | 2026-03-29 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/implementing-plan-phases.test.ts` | Validates SKILL.md frontmatter, sections, branch naming, status workflow, PR creation step, allowed-tools, references, assets, and ai-skills-manager validation | PASS |
| `scripts/__tests__/build.test.ts` | Build/validation pipeline for all plugins | PASS |
| `scripts/__tests__/orchestrating-workflows.test.ts` | Orchestrating workflows skill tests (regression — no changes expected) | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| No new automated tests required — this chore changes instruction wording only, not code logic. Existing validation tests cover structural integrity. | N/A | All ACs | Low | -- |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| No automated test can verify that Claude interprets "always commit" language correctly — this is a prompt-engineering change | SKILL.md, step-details.md, workflow-example.md | AC1, AC2, AC3 | Manual verify via code review that wording is unambiguous |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| AC1 | SKILL.md commit-and-push step uses explicit "always" / "do not ask" language | `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` — Quick Start step 9 and Workflow checklist | Code review: grep for "always" and "do not ask" or equivalent directive near commit-and-push step | PASS |
| AC2 | step-details.md reinforces mandatory commit-push with no-confirmation directive | `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` — Step 9 section | Code review: Step 9 intro paragraph includes mandatory/no-confirmation language | PASS |
| AC3 | workflow-example.md reflects the mandatory commit-push behavior | `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/workflow-example.md` — Section 9 and Result section | Code review: example step 9 and Result section reflect mandatory commit-push | PASS |
| AC4 | Commit-push is a blocking requirement before phase status can be updated to Complete | `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` — Verification section; `references/step-details.md` — Step 10 | Code review: Step 10 or Verification section states commit-push must succeed before marking Complete | PASS |
| AC5 | No duplicate commit-push instructions in orchestrating-workflows | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | Grep for "commit" and "push" — expect no matches (already confirmed pre-chore) | PASS |
| AC6 | Validation passes (`npm run validate`) | All plugin files | Automated: `npm run validate` exits 0 | PASS |

## Deliverable Verification

| Deliverable | Source | Expected Path | Status |
|-------------|--------|---------------|--------|
| Updated SKILL.md with mandatory commit-push language | CHORE-030 AC1, AC4 | `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` | PASS |
| Updated step-details.md with no-confirmation directive | CHORE-030 AC2 | `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` | PASS |
| Updated workflow-example.md with mandatory behavior | CHORE-030 AC3 | `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/workflow-example.md` | PASS |

## Verification Checklist

- [x] All existing tests pass (`npm test`)
- [x] Plugin validation passes (`npm run validate`)
- [x] SKILL.md Quick Start step 9 contains mandatory commit-push language
- [x] SKILL.md Workflow checklist contains mandatory commit-push language
- [x] SKILL.md Verification section lists commit-push as blocking for phase completion
- [x] step-details.md Step 9 contains no-confirmation directive
- [x] workflow-example.md section 9 reflects mandatory behavior
- [x] workflow-example.md Result section reflects mandatory commit-push
- [x] orchestrating-workflows SKILL.md contains no commit/push instructions
- [x] Lint passes (`npm run lint`)

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
