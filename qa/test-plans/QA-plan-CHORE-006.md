# QA Test Plan: Migrate Jest to Vitest

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-CHORE-006 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-006 |
| **Source Documents** | `requirements/chores/CHORE-006-migrate-jest-to-vitest.md` |
| **Date Created** | 2026-03-28 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/build.test.ts` | Build/validation pipeline | PENDING |
| `scripts/__tests__/constants.test.ts` | Path constants and helpers | PENDING |
| `scripts/__tests__/creating-implementation-plans.test.ts` | Implementation plan skill | PENDING |
| `scripts/__tests__/documenting-bugs.test.ts` | Bug documentation skill (uses `it.each`) | PENDING |
| `scripts/__tests__/documenting-chores.test.ts` | Chore documentation skill | PENDING |
| `scripts/__tests__/documenting-features.test.ts` | Feature documentation skill | PENDING |
| `scripts/__tests__/documenting-qa.test.ts` | QA documentation skill | PENDING |
| `scripts/__tests__/executing-bug-fixes.test.ts` | Bug fix execution skill | PENDING |
| `scripts/__tests__/executing-chores.test.ts` | Chore execution skill | PENDING |
| `scripts/__tests__/executing-qa.test.ts` | QA execution skill | PENDING |
| `scripts/__tests__/git-utils.test.ts` | Git utility functions | PENDING |
| `scripts/__tests__/implementing-plan-phases.test.ts` | Phase implementation skill | PENDING |
| `scripts/__tests__/prompts.test.ts` | CLI print utilities | PENDING |
| `scripts/__tests__/qa-verifier.test.ts` | QA verifier tool | PENDING |
| `scripts/__tests__/release-tag.test.ts` | Release tagging | PENDING |
| `scripts/__tests__/release.test.ts` | Release workflow | PENDING |
| `scripts/__tests__/scaffold.test.ts` | Skill scaffolding | PENDING |
| `scripts/__tests__/skill-utils.test.ts` | Skill discovery utilities | PENDING |

## New Test Analysis

No new tests are required for this chore. The migration replaces the test runner without changing test logic. All existing tests serve as verification that the migration succeeded.

| Test Description | Target File(s) | Requirement Ref | Priority |
|-----------------|----------------|-----------------|----------|
| N/A — existing tests are the verification | — | — | — |

## Coverage Gap Analysis

No coverage gaps introduced by this chore. The migration is framework-level; test coverage of application code is unchanged.

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| N/A — no new code paths | — | — | — |

## Code Path Verification

Traceability from acceptance criteria to implementation:

| Requirement | Description | Expected Code Path | Verification Method |
|-------------|-------------|-------------------|-------------------|
| AC-1 | All 18 test files pass with Vitest | All files in `scripts/__tests__/` | Run `npm test` and verify 18 files pass with 0 failures |
| AC-2 | `npm test` runs tests via Vitest | `package.json` scripts.test | Verify `package.json` "test" script invokes `vitest run` (not jest) |
| AC-3 | Jest config and dependencies fully removed | `package.json`, `jest.config.js` | Verify `jest.config.js` does not exist; verify `jest`, `ts-jest`, `@types/jest` absent from `package.json` devDependencies |
| AC-4 | Sequential test execution preserved | `vitest.config.ts` | Verify Vitest config enforces sequential execution (e.g., `fileParallelism: false` or equivalent); run tests and confirm no race conditions |
| AC-5 | No `--experimental-vm-modules` flag needed | `package.json` scripts | Verify no test script in `package.json` contains `--experimental-vm-modules` |
| AC-6 | `vitest.config.ts` created with equivalent settings | `vitest.config.ts` | Verify file exists with: test match pattern `**/__tests__/**/*.test.ts`, sequential execution, coverage config for `scripts/**/*.ts` |
| AC-7 | Build and lint pass after migration | Full project | Run `npm run lint` and `npm run validate` — both must succeed |

## Deliverable Verification

| Deliverable | Source | Expected Path | Exists |
|-------------|--------|---------------|--------|
| Vitest config file | AC-6 | `vitest.config.ts` | PENDING |
| Updated package.json | AC-2, AC-3, AC-5 | `package.json` | PENDING |
| Updated CLAUDE.md | Affected Files | `CLAUDE.md` | PENDING |
| Removed Jest config | AC-3 | `jest.config.js` (should NOT exist) | PENDING |

## Scope Verification

Confirm no unrelated changes were introduced:

| Check | Description | Verification Method |
|-------|-------------|-------------------|
| Test behavior unchanged | Tests assert the same conditions before and after migration | Code review: no test logic changes beyond import additions |
| Application code untouched | No changes to `scripts/lib/`, `scripts/build.ts`, `scripts/scaffold.ts` | `git diff` shows no changes to non-test, non-config files |
| `it.each()` compatibility | 3 parameterized test instances in `documenting-bugs.test.ts` work identically | Verify `documenting-bugs.test.ts` passes with all parameterized cases |

## Verification Checklist

- [ ] All 18 existing tests pass under Vitest (regression baseline — AC-1)
- [ ] All 7 acceptance criteria have corresponding test plan entries (AC-1 through AC-7)
- [ ] Coverage gaps are identified with recommendations (none for this chore)
- [ ] Code paths trace from acceptance criteria to implementation (7 entries)
- [ ] Deliverables are accounted for (4 entries)
- [ ] Scope verification confirms no unrelated changes (3 checks)
