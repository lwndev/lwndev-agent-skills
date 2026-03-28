# QA Test Plan: QA Executes Coverage Audit Instead of Test Plan

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-BUG-003 |
| **Requirement Type** | BUG |
| **Requirement ID** | BUG-003 |
| **Source Documents** | `requirements/bugs/BUG-003-qa-coverage-audit-not-execution.md` |
| **Date Created** | 2026-03-28 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/qa-verifier.test.ts` | Validates qa-verifier agent definition file structure, tools, and verification responsibilities | PENDING |
| `scripts/__tests__/executing-qa.test.ts` | Validates executing-qa skill structure, allowed tools, stop hook, test results template, and validation | PENDING |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority |
|-----------------|----------------|-----------------|----------|
| qa-verifier responsibilities section describes direct test plan entry verification instead of test suite execution | `plugins/lwndev-sdlc/agents/qa-verifier.md` | RC-1, AC-3 | High |
| qa-verifier does not have "Run `npm test`" as its primary Step 1 action | `plugins/lwndev-sdlc/agents/qa-verifier.md` | RC-1, AC-7 | High |
| executing-qa SKILL.md describes iterating through test plan entries for direct verification | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | RC-2, AC-1 | High |
| executing-qa auto-fix loop addresses verification failures (not test writing) | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | RC-2, AC-4 | High |
| executing-qa Stop hook evaluates direct test plan execution results | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | RC-3, AC-5 | High |
| test results template contains per-entry PASS/FAIL structure | `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template.md` | AC-6 | High |
| qa-verifier.test.ts updated to reflect new direct-verification responsibilities | `scripts/__tests__/qa-verifier.test.ts` | RC-1 | Medium |
| executing-qa.test.ts updated to reflect new verification behavior and template structure | `scripts/__tests__/executing-qa.test.ts` | RC-2, RC-3 | Medium |

## Verification Checklist

- [ ] All existing tests pass (regression baseline)
- [ ] All RC-N entries (RC-1, RC-2, RC-3) have corresponding test plan entries
- [ ] All AC entries (AC-1 through AC-7) have corresponding test plan entries
- [ ] Coverage gaps are identified with recommendations
- [ ] Code paths trace from root causes to implementation
- [ ] Deliverables are accounted for
- [ ] Reproduction steps are verified as no longer reproducing
- [ ] New test recommendations are actionable and prioritized
