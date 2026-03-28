# QA Test Plan: Test-Plan Reconciliation Mode

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-CHORE-022 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-022 |
| **Source Documents** | `requirements/chores/CHORE-022-test-plan-reconciliation.md` |
| **Date Created** | 2026-03-22 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/build.test.ts` | Validates all plugins including reviewing-requirements skill directory existence and SKILL.md frontmatter | PENDING |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority |
|-----------------|----------------|-----------------|----------|
| No new automated tests required — this chore modifies skill prompt files (SKILL.md, template, example), not executable code | N/A | All ACs | N/A |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| Reconciliation mode behavior is defined in SKILL.md prompt instructions, not executable code — coverage is verified by manual skill invocation | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | AC1-AC6, AC9-AC10 | Manual verification via skill invocation with a requirement that has an existing test plan |
| Workflow diagram correctness cannot be unit tested | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` (Relationship to Other Skills section) | AC8 | Code review |

## Code Path Verification

Traceability from acceptance criteria to implementation:

| Requirement | Description | Expected Code Path | Verification Method |
|-------------|-------------|-------------------|-------------------|
| AC1 | Skill automatically enters test-plan reconciliation mode when a QA test plan exists | `SKILL.md` — new step or conditional in Step 1/Step 2 that checks for `qa/test-plans/QA-plan-{ID}.md` and branches into reconciliation mode | Code review: verify SKILL.md contains mode detection logic that checks for test plan existence |
| AC2 | Cross-references between test plan entries and requirement traceability IDs validated bidirectionally | `SKILL.md` — new reconciliation step that maps test plan entries → FR-N/RC-N/AC and FR-N/RC-N/AC → test plan entries | Code review: verify SKILL.md describes bidirectional cross-reference checks |
| AC3 | New scenarios/edge cases from test plan flagged as backporting candidates | `SKILL.md` — reconciliation step that identifies test plan entries without a corresponding requirement and flags them | Code review: verify SKILL.md includes drift detection that flags test-plan-only scenarios |
| AC4 | Gaps where requirements lack test plan coverage are reported | `SKILL.md` — reconciliation step that identifies FR-N/RC-N/AC entries without corresponding test plan entries | Code review: verify SKILL.md includes gap analysis from requirements → test plan direction |
| AC5 | Contradictions between test plan expectations and requirements are reported | `SKILL.md` — reconciliation step that compares expected behavior in test plan vs. requirements | Code review: verify SKILL.md includes contradiction detection logic |
| AC6 | Findings include actionable suggestions for updating requirements docs, GitHub issues, and implementation plans | `SKILL.md` — reconciliation findings format includes suggestion field targeting specific artifacts | Code review: verify finding format in SKILL.md and `assets/review-findings-template.md` includes suggestion targets |
| AC7 | Existing standard review behavior unchanged when no test plan exists | `SKILL.md` — conditional branching only activates reconciliation when test plan is found; all existing Steps 1-9 remain intact | Code review: verify existing steps are unmodified and new mode is additive |
| AC8 | "Relationship to Other Skills" section updated to reflect new workflow position | `SKILL.md` — workflow diagrams show reviewing-requirements can appear after documenting-qa | Code review: verify updated workflow chains in SKILL.md |
| AC9 | Severity classification (Error/Warning/Info) applies to reconciliation findings | `SKILL.md` — reconciliation findings use the same severity table as standard review; `assets/review-findings-template.md` — template accommodates reconciliation findings | Code review: verify severity classification is applied to reconciliation findings |
| AC10 | Gap analysis findings distinguished from standard review Step 6 findings | `SKILL.md` — reconciliation gap analysis explicitly references `qa/test-plans/QA-plan-{ID}.md` as its target, not the inline Testing Requirements section | Code review: verify reconciliation gap analysis step is distinct from Step 6 and references the QA test plan document |

## Deliverable Verification

| Deliverable | Source | Expected Path | Exists |
|-------------|--------|---------------|--------|
| Updated SKILL.md with reconciliation mode | CHORE-022 | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | YES (to be modified) |
| Updated findings template | CHORE-022 | `plugins/lwndev-sdlc/skills/reviewing-requirements/assets/review-findings-template.md` | YES (to be modified) |
| Updated review example | CHORE-022 | `plugins/lwndev-sdlc/skills/reviewing-requirements/references/review-example.md` | YES (to be modified) |

## Scope Verification

Confirm no unrelated changes are introduced:

| Scope Check | Verification Method |
|-------------|-------------------|
| No other skills under `plugins/lwndev-sdlc/skills/` are modified | `git diff --stat` shows only reviewing-requirements files changed |
| No build/scaffold scripts modified | `git diff --stat` excludes `scripts/` changes |
| No test files modified | `git diff --stat` excludes `scripts/__tests__/` changes |
| No plugin manifest modified | `git diff --stat` excludes `.claude-plugin/plugin.json` changes |
| Build validation still passes | `npm run validate` succeeds after changes |

## Verification Checklist

- [ ] All existing tests pass (regression baseline)
- [ ] All AC entries (AC1-AC10) have corresponding test plan entries
- [ ] Coverage gaps are identified with recommendations
- [ ] Code paths trace from acceptance criteria to implementation
- [ ] Deliverables are accounted for
- [ ] Scope verification confirms no unrelated changes
- [ ] New test recommendations are actionable and prioritized
