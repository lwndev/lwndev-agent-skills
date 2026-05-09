---
id: BUG-017
version: 2
timestamp: 2026-05-09T22:01:30Z
persona: qa
---

## User Summary

`tests/unit/argument-hint.test.ts` and `tests/unit/build.test.ts` hardcode the skill count to `13` in multiple assertions, so adding a 14th skill produces 50+ cascading failures in tests that have nothing to do with skill count. The fix replaces hardcoded counts with a derivation from the actual `plugins/lwndev-sdlc/skills/` directory, aligns the `_`-prefix readdir filter in `build.test.ts` with `argument-hint.test.ts` and `getSourceSkills`, and decouples the dependent describe blocks in `argument-hint.test.ts` from the brittle prerequisite so that one drift never cascades.

## Capability Report

```json
{
  "id": "BUG-017",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript"
}
```

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Scenarios (by dimension)

### Inputs

- [P0] Plugin skills directory contains exactly N real skills with no `.`-prefix or `_`-prefix entries; both test files derive count = N and assert successfully | mode: test-framework | expected: vitest assertion that the derived count expression returns the same N as `getSourceSkills('lwndev-sdlc').length` and that all relevant assertions pass
- [P0] Plugin skills directory contains a `.`-prefix entry (e.g., `.cache/`) alongside N real skills; derived count = N (the dot entry is filtered) | mode: test-framework | expected: vitest test that materializes a `.cache/` dir under a tmp fixture, runs the count derivation, asserts `count === realSkillsCount`
- [P0] Plugin skills directory contains a `_`-prefix entry (e.g., `_archived/`) alongside N real skills; derived count = N in BOTH `argument-hint.test.ts` AND `build.test.ts` (this is the regression that motivated the bug — `build.test.ts` filters were missing this exclusion) | mode: test-framework | expected: vitest test that materializes a `_archived/` dir, exercises the derivation in both files' execution paths, asserts both report the same N
- [P1] Plugin skills directory contains a non-directory entry (a stray file like `README.md` or `.DS_Store`); derived count excludes it | mode: test-framework | expected: vitest test that drops a regular file at the skills root, asserts derivation still equals real skill count
- [P1] Plugin skills directory contains a directory whose name is exactly `_` or exactly `.` (single character); filter excludes it | mode: test-framework | expected: vitest fixture with `_` and `.` directory names, count derivation filters both
- [P1] Plugin skills directory is empty; both tests fail with a clear error rather than asserting `expect(0).toBe(0)` and silently passing | mode: test-framework | expected: vitest test that runs the suite against an empty fixture skills dir, asserts the test setup detects the empty case and fails fast
- [P2] Skill directory name contains Unicode (e.g., `dökumenting-features`); filter does not strip non-ASCII | mode: test-framework | expected: vitest fixture with one Unicode-named skill dir, derivation includes it in the count
- [P2] Skill directory name has trailing whitespace or zero-width characters; filter behaves predictably (typically does NOT exclude based on whitespace) | mode: exploratory | expected: manual confirmation that whitespace edge cases match the documented `getSourceSkills` semantics

### State transitions

- [P0] Forced failure at `argument-hint.test.ts:41` (the loader assertion) does NOT cascade beyond 1 failed test — the dependent describe blocks (`frontmatter presence`, `hint value constraints`, `YAML quoting for bracket values`, `argument-handling instructions in SKILL.md body`) still run and pass independently (RC-3 acceptance) | mode: test-framework | expected: temporary mutation of line 41 to `expect(false).toBe(true)` (or its equivalent) in a fixture-driven sub-suite, asserts total failure count <= 1 in the run
- [P1] Skills are added to the directory mid-run between two `describe` blocks (filesystem mutation during a single test session); the count assertion remains internally consistent within each describe (each block re-derives independently) | mode: test-framework | expected: vitest test using fs mocks or a tmp dir to simulate mutation between blocks, asserts no flakiness from mutation
- [P1] Re-running the full `npm run test:unit` immediately after a successful run with no code changes still passes (idempotency) | mode: test-framework | expected: existing CI behavior; verify by running `npm run test:unit` twice in a row locally
- [P2] Vitest parallel mode (the project enabled `fileParallelism: true` in CHORE-038) does not introduce a race between argument-hint.test.ts and build.test.ts loading the skills dir | mode: test-framework | expected: confirm both test files use only read-only access to `plugins/lwndev-sdlc/skills` and don't write fixtures into the production tree

### Environment

- [P1] `plugins/lwndev-sdlc/skills` is a symbolic link rather than a real directory; readdir resolution still works | mode: exploratory | expected: manual reproduction; replace `plugins/lwndev-sdlc/skills` with a symlink to a directory containing the same skills, run the suite
- [P1] Skill subdirectory is itself a symlink to another location; `e.isDirectory()` still classifies it correctly | mode: test-framework | expected: vitest fixture using `symlink()` from `node:fs/promises`, asserts derivation count includes the symlinked skill
- [P2] Read permission on `plugins/lwndev-sdlc/skills` is restricted (`chmod 000`); test produces a clear error with file path, not a generic "expected 13, got 0" | mode: exploratory | expected: manual reproduction with `chmod 000` then `npm run test:unit`; assert error mentions `EACCES` and the offending path
- [P2] `PLUGINS_DIR` env var is set to a different directory; tests still derive against `plugins/lwndev-sdlc/skills` (the tests in scope are NOT parameterized by `PLUGINS_DIR` — only the validate script is) | mode: test-framework | expected: vitest test that sets `PLUGINS_DIR=/tmp/something` in process env and asserts the unit test still reads from the canonical project skills dir

### Dependency failure

- [P1] `npm run validate` (invoked by `build.test.ts:beforeAll`) emits no `Validating: ` lines (e.g., zero skills present); the count assertion fails with a meaningful error rather than `expect(0).toBe(0)` passing trivially | mode: test-framework | expected: vitest test where the validate output is mocked to empty; assert the count assertion fails with a useful diagnostic
- [P1] `npm run validate` emits extra `Validating: ` lines outside the lwndev-sdlc plugin (e.g., a future second plugin); the count derivation accounts for this (or the test scope is explicitly limited to one plugin) | mode: test-framework | expected: vitest test with mocked validate output containing two plugins; asserts the test correctly counts only the in-scope plugin's skills
- [P2] `gray-matter` parser throws on a malformed `SKILL.md` frontmatter; the loader at `argument-hint.test.ts:30-39` surfaces the error rather than producing a partially-populated `skillData` map | mode: test-framework | expected: vitest fixture with one `SKILL.md` containing intentionally broken YAML, asserts the loader fails fast with the offending file path

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P1] Race condition between vitest parallel test files: both `argument-hint.test.ts` and `build.test.ts` read `plugins/lwndev-sdlc/skills` concurrently; neither writes to it, so concurrent readdir is safe — verify by running the suite under `--reporter=verbose` with high `--concurrency` | mode: exploratory | expected: manual run with elevated concurrency; assert no flakiness across 5 consecutive runs
- [P2] Future skill directory names that include reserved characters on Windows (`con`, `aux`, `nul`); test passes on macOS/Linux but fails informatively on Windows | mode: exploratory | expected: documented as Windows-untested; verify CI matrix coverage
- [P2] Documentation precision: the test file change must not alter the exported skill list shape consumed by `scripts/lib/skill-utils.ts:getSourceSkills` | mode: test-framework | expected: existing tests for `getSourceSkills` continue to pass after the change

## Non-applicable dimensions

- a11y: this change touches only test files and has no UI surface, screen-reader output, or keyboard interaction
- i18n: skill directory names are ASCII-only by convention and not user-facing locale-sensitive strings; the Unicode and RTL probes under Inputs cover the only locale-adjacent risk (filesystem encoding of skill directory names)
