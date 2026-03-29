# QA Test Plan: Align Pre-commit Lint With CI

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-CHORE-028 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-028 |
| **Source Documents** | `requirements/chores/CHORE-028-align-precommit-lint-with-ci.md` |
| **Date Created** | 2026-03-29 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

All existing tests in `scripts/__tests__/` must continue to pass. This is a configuration-only change to `.husky/pre-commit` — no application code is modified, so the full test suite serves as a regression baseline.

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/*.test.ts` (all 23 files) | Full test suite — regression baseline | PENDING |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| No new automated tests required — this chore modifies a shell hook file, not application code. Verification is via manual inspection and execution. | `.husky/pre-commit` | AC1-AC5 | High | -- |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| Pre-commit hook is a shell script not covered by unit tests | `.husky/pre-commit` | AC1-AC5 | Manual verification: inspect file contents and execute hook on clean working tree |

## Code Path Verification

Traceability from requirements to implementation (one entry per AC):

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| AC1 | Pre-commit hook runs `npm run lint` in addition to `lint-staged` | `.husky/pre-commit` contains `npm run lint` line | Code review — inspect file for `npm run lint` line | -- |
| AC2 | Pre-commit hook runs `npm run format:check` in addition to `lint-staged` | `.husky/pre-commit` contains `npm run format:check` line | Code review — inspect file for `npm run format:check` line | -- |
| AC3 | Lint and format steps match CI | `.husky/pre-commit` lint/format commands match `.github/workflows/ci.yml` steps | Code review — compare pre-commit commands against CI workflow `Lint` and `Check formatting` steps | -- |
| AC4 | All existing pre-commit steps preserved | `.husky/pre-commit` still contains `npx lint-staged`, `npm test`, `npm audit` | Code review — confirm all three original lines remain | -- |
| AC5 | Pre-commit hook executes successfully on clean working tree | `.husky/pre-commit` runs without errors | Manual — run `bash .husky/pre-commit` on clean tree and verify exit code 0 | -- |

## Deliverable Verification

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| Updated pre-commit hook | CHORE-028 | `.husky/pre-commit` | -- |

## Scope Verification

Confirm no unrelated changes are introduced:

| Check | Description | Verification Method | Status |
|-------|-------------|-------------------|--------|
| No CI changes | `.github/workflows/ci.yml` should remain unchanged | Code review — confirm file is not in the diff | -- |
| No package.json changes | `package.json` scripts and lint-staged config should remain unchanged | Code review — confirm file is not in the diff | -- |
| No other files modified | Only `.husky/pre-commit` should be changed | Code review — check PR diff for unexpected files | -- |
| Step ordering | Commands appear in this exact order: `npx lint-staged` → `npm run lint` → `npm run format:check` → `npm test` → `npm audit --audit-level=high` | Code review — inspect line order in `.husky/pre-commit` matches this sequence | -- |
| Audit flag divergence | CI runs `npm audit` (no flag); pre-commit runs `npm audit --audit-level=high`. This divergence is out of scope for CHORE-028 (AC3 targets lint and format steps only). | Code review — confirm `npm audit --audit-level=high` is preserved unchanged (AC4) | -- |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
