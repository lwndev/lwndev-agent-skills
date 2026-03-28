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

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| No test verifies that qa-verifier describes direct condition checking as its primary method | `plugins/lwndev-sdlc/agents/qa-verifier.md` | RC-1 | Content verification in qa-verifier.test.ts |
| No test verifies executing-qa describes per-entry iteration through the test plan | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | RC-2, AC-1 | Content verification in executing-qa.test.ts |
| No test verifies the auto-fix loop does not reference writing automated tests | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | RC-2, AC-4 | Content verification in executing-qa.test.ts |
| No test verifies the Stop hook references direct test plan execution results | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | RC-3, AC-5 | Content verification in executing-qa.test.ts |
| No test verifies test results template has per-entry PASS/FAIL sections | `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template.md` | AC-6 | Content verification in executing-qa.test.ts |

## Code Path Verification

Traceability from root causes to implementation:

| Requirement | Description | Expected Code Path | Verification Method |
|-------------|-------------|-------------------|-------------------|
| RC-1 | qa-verifier designed as test runner/coverage auditor instead of direct verifier | `plugins/lwndev-sdlc/agents/qa-verifier.md` — Responsibilities section, Step 1, verification process | Verify file content: responsibilities describe direct condition checking (reading files, checking behavior); Step 1 is NOT "Run `npm test`" as primary action; verification process describes iterating test plan entries |
| RC-2 | executing-qa delegates to coverage-audit subagent and auto-fixes by writing tests | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — Step 2 verification loop, auto-fix section | Verify file content: Step 2 describes iterating test plan entries directly; auto-fix addresses verification failures (missing content, unmet conditions) not test writing; delegation instructions align with direct verification |
| RC-3 | Stop hook gates on coverage-audit verdict instead of direct execution results | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — hooks frontmatter | Verify file content: Stop hook prompt evaluates whether test plan entries have been directly verified with PASS/FAIL results, not whether qa-verifier returned a coverage-audit pass |

## Deliverable Verification

| Deliverable | Source | Expected Path | Exists |
|-------------|--------|---------------|--------|
| Rewritten qa-verifier agent | RC-1 fix | `plugins/lwndev-sdlc/agents/qa-verifier.md` | PENDING |
| Updated executing-qa skill | RC-2, RC-3 fix | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | PENDING |
| Updated test results template | AC-6 fix | `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template.md` | PENDING |
| Updated qa-verifier tests | Regression | `scripts/__tests__/qa-verifier.test.ts` | PENDING |
| Updated executing-qa tests | Regression | `scripts/__tests__/executing-qa.test.ts` | PENDING |

## Reproduction Verification

Confirm the bug no longer reproduces after the fix:

| Step | Verification | Expected Outcome |
|------|-------------|-----------------|
| Read qa-verifier agent responsibilities section | Check primary responsibilities | Should describe direct test plan entry verification (reading files, checking conditions), NOT test suite execution and coverage auditing |
| Read qa-verifier verification process | Check Step 1 and overall flow | Should describe iterating through test plan entries and directly verifying each condition; `npm test` may appear but NOT as the primary/first action |
| Read executing-qa Step 2 verification loop | Check delegation instructions and iteration approach | Should describe iterating through each test plan entry and directly verifying it, NOT delegating to a coverage auditor |
| Read executing-qa auto-fix section | Check what the auto-fix loop does | Should address direct verification failures (e.g., file content not matching, conditions unmet), NOT write missing automated tests |
| Read executing-qa Stop hook prompt | Check completion criteria | Should evaluate whether test plan entries have been directly verified with per-entry PASS/FAIL, NOT whether a coverage-audit verdict was clean |
| Read test results template | Check results structure | Should contain per-entry PASS/FAIL rows for each test plan entry, NOT just aggregate test suite counts and coverage gap tables |

## Verification Checklist

- [ ] All existing tests pass (regression baseline)
- [ ] All RC-N entries (RC-1, RC-2, RC-3) have corresponding test plan entries
- [ ] All AC entries (AC-1 through AC-7) have corresponding test plan entries
- [ ] Coverage gaps are identified with recommendations
- [ ] Code paths trace from root causes to implementation
- [ ] Deliverables are accounted for
- [ ] Reproduction steps are verified as no longer reproducing
- [ ] New test recommendations are actionable and prioritized
