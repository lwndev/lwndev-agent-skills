# Chore: Migrate Jest to Vitest

## Chore ID

`CHORE-006`

## GitHub Issue

[#11](https://github.com/lwndev/lwndev-marketplace/issues/11)

## Category

`configuration`

## Description

Migrate the test framework from Jest (v30 + ts-jest) to Vitest for native ESM and TypeScript support, eliminating the need for `--experimental-vm-modules` and `ts-jest` configuration overhead.

## Affected Files

- `package.json` (replace dependencies and test scripts)
- `package-lock.json` (dependency tree update)
- `jest.config.js` (remove, replace with `vitest.config.ts`)
- `CLAUDE.md` (update `maxWorkers: 1` reference to Vitest equivalent)
- `scripts/__tests__/build.test.ts`
- `scripts/__tests__/constants.test.ts`
- `scripts/__tests__/creating-implementation-plans.test.ts`
- `scripts/__tests__/documenting-bugs.test.ts`
- `scripts/__tests__/documenting-chores.test.ts`
- `scripts/__tests__/documenting-features.test.ts`
- `scripts/__tests__/documenting-qa.test.ts`
- `scripts/__tests__/executing-bug-fixes.test.ts`
- `scripts/__tests__/executing-chores.test.ts`
- `scripts/__tests__/executing-qa.test.ts`
- `scripts/__tests__/git-utils.test.ts`
- `scripts/__tests__/implementing-plan-phases.test.ts`
- `scripts/__tests__/prompts.test.ts`
- `scripts/__tests__/qa-verifier.test.ts`
- `scripts/__tests__/release-tag.test.ts`
- `scripts/__tests__/release.test.ts`
- `scripts/__tests__/scaffold.test.ts`
- `scripts/__tests__/skill-utils.test.ts`

## Acceptance Criteria

- [x] All 18 test files pass with Vitest
- [x] `npm test` runs tests via Vitest
- [x] Jest config (`jest.config.js`) and dependencies (`jest`, `ts-jest`, `@types/jest`) are fully removed
- [x] Sequential test execution is preserved (to prevent race conditions with shared `plugins/` directories)
- [x] No `--experimental-vm-modules` flag needed in test scripts
- [x] `vitest.config.ts` created with equivalent settings
- [x] Build and lint pass after migration

## Completion

**Status:** `Completed`

**Completed:** 2026-03-28

**Pull Request:** [#75](https://github.com/lwndev/lwndev-marketplace/pull/75)

## Notes

- No mocks or spies are used in the test suite, making this a straightforward migration
- `it.each()` is used in 3 instances; Vitest supports the same API
- Sequential execution must be preserved to prevent race conditions with shared `plugins/` directories. The current Jest config uses `maxWorkers: 1`; the Vitest equivalent should be validated during implementation (e.g., `pool: 'forks'` with `poolOptions.forks.singleFork: true`, or `fileParallelism: false`)
- All test imports need `import { describe, it, expect, ... } from 'vitest'` added since Jest uses globals
