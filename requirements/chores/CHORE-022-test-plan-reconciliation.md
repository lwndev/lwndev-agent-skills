# Chore: Test-Plan Reconciliation Mode

## Chore ID

`CHORE-022`

## GitHub Issue

[#64](https://github.com/lwndev/lwndev-marketplace/issues/64)

## Category

`refactoring`

## Description

Add a test-plan reconciliation mode to the `reviewing-requirements` skill so it can run after `/documenting-qa` to detect drift, gaps, inconsistencies, and informational updates between the QA test plan and upstream artifacts (requirements, GitHub issues, implementation plans).

## Affected Files

- `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md`
- `plugins/lwndev-sdlc/skills/reviewing-requirements/assets/review-findings-template.md`
- `plugins/lwndev-sdlc/skills/reviewing-requirements/references/review-example.md`

## Acceptance Criteria

- [x] When a QA test plan exists for the given requirement ID, the skill automatically enters test-plan reconciliation mode
- [x] Cross-references between test plan entries and requirement traceability IDs (FR-N, RC-N, AC) are validated bidirectionally
- [x] New scenarios or edge cases introduced by the test plan are flagged as candidates for backporting to requirements
- [x] Gaps where requirements lack test plan coverage are reported
- [x] Contradictions between test plan expectations and requirements are reported
- [x] Findings include actionable suggestions for updating requirements docs, GitHub issues, and implementation plans
- [x] Existing standard review behavior is unchanged when no test plan exists
- [x] The "Relationship to Other Skills" section in SKILL.md is updated to reflect the new workflow position
- [x] Severity classification (Error/Warning/Info) applies to reconciliation findings using the same conventions as standard review
- [x] Gap analysis findings are clearly distinguished from standard review Step 6 ("Untested Paths") findings, referencing the QA test plan rather than the inline Testing Requirements section

## Completion

**Status:** `Completed`

**Completed:** 2026-03-22

**Pull Request:** [#68](https://github.com/lwndev/lwndev-marketplace/pull/68)

## Notes

- The skill will operate in two modes: **standard review** (no test plan exists — current behavior) and **test-plan reconciliation** (test plan exists at `qa/test-plans/QA-plan-{ID}.md`).
- Test-plan reconciliation gap analysis targets the QA test plan document, which is distinct from standard review Step 6 that checks the requirements document's inline "Testing Requirements" section.
- Related issues: #66 (code-review reconciliation mode), #67 (workflow chain updates across all skills).
