---
id: FEAT-031
version: 2
timestamp: 2026-05-02T18:57:30Z
persona: qa
---

## User Summary

FEAT-031 collapses two divergent test trees (TS under `scripts/__tests__/`, Bats under `plugins/lwndev-sdlc/.../tests/`) into a single `tests/` root with runner-scoped leaves (`tests/unit/` for Vitest, `tests/bats/` for Bats), unifies `npm test` to drive both runners, and ships a layout validator + PreToolUse enforcement hook so misplaced test files cannot regress. From the contributor's view, tests live in one predictable place and a single `npm test` runs everything; from the `/plugin install` user's view, the installed plugin payload no longer contains contributor-only test files.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Scenarios (by dimension)

### Inputs

- [P0] Validator classifies a `.test.ts` placed at repo root, under `scripts/`, or under `plugins/` as `ts-outside-tests-unit` and exits non-zero | mode: test-framework | expected: child-process spawn against synthetic tree; assert exit 1 and rule ID in stdout
- [P0] Validator classifies any `.spec.ts` outside the documented allow-rule path as `spec-extension-disallowed` | mode: test-framework | expected: synthetic tree with `foo.spec.ts` at multiple roots; assert rule fires for each
- [P0] Validator allow-rule preserves the `feat-030-known-buggy/__tests__/qa-buggy.spec.ts` fixture path — clean exit 0 even though extension would otherwise fire | mode: test-framework | expected: synthetic tree containing only the fixture path; assert exit 0 and zero violations
- [P0] Validator classifies a `.bats` placed under `plugins/` or `scripts/` as `bats-outside-tests-bats` | mode: test-framework | expected: synthetic tree with misplaced `.bats`; assert rule and exit 1
- [P0] Hook rejects `Write` to `scripts/foo.test.ts` and `plugins/lwndev-sdlc/skills/x/scripts/tests/y.bats` with rule + canonical-destination message | mode: test-framework | expected: stdin-fed JSON; assert non-zero exit and message contains rule ID + canonical path
- [P1] Hook treats unrelated edits (`README.md`, `scripts/build.ts`, `package.json`) as no-ops with exit 0 | mode: test-framework | expected: stdin-fed JSON for each non-test path; assert exit 0 and silent stdout
- [P1] Hook fail-open contract — malformed JSON, missing `tool_input`, missing `file_path`, empty `file_path`, null value all exit 0 with no rejection | mode: test-framework | expected: stdin variants per Edge Case 4; assert exit 0
- [P1] Validator handles paths with spaces, parentheses, single quotes, and Unicode characters without crashing the glob walker | mode: test-framework | expected: synthetic tree containing `tests/unit/foo bar.test.ts` and `tests/unit/résumé.test.ts`; assert validator runs to completion and rule firing is correct (clean for these correctly-placed files)
- [P1] Validator handles a deeply-nested misplaced path (e.g., `plugins/a/b/c/d/e/foo.test.ts`) and reports the full path in the FAIL line | mode: test-framework | expected: synthetic tree at depth 5; assert path string in stdout matches input verbatim
- [P2] Validator output remains stable across multiple runs (no nondeterministic order) — useful for `git diff`-style comparison | mode: test-framework | expected: run validator twice on identical tree; assert byte-equal stdout
- [P2] Validator handles a symlinked test file whose link target is outside `tests/unit/` — confirm whether classification follows symlink or treats as the link path | mode: exploratory | expected: documented behavior in PR body so reviewers understand which path the rule reports
- [P2] Hook accepts very long `file_path` strings (1KB+) without truncation or rejection mismatch | mode: test-framework | expected: stdin-fed long path; assert correct rule firing
- [P2] Validator distinguishes `.test.tsx` from `.test.ts` — confirm `.test.tsx` is **not** classified by the layout rule (FEAT-031 inventory has zero `.tsx` test files) | mode: test-framework | expected: synthetic `foo.test.tsx` outside `tests/unit/`; assert no violation reported (or document expected rule)

### State transitions

- [P0] After Phase 1's transitional dual-include `testMatch`, `npm test` discovers the moved files **once** and not duplicated under both globs (Phase 1 risk-table item) | mode: test-framework | expected: post-Phase-1 commit boundary; assert Vitest test count equals the pre-Phase-1 baseline (NFR-1)
- [P0] After Phase 3 narrows `testMatch` to `tests/unit/**/*.test.ts`, no leftover file under the legacy globs runs — the legacy globs no longer match anything | mode: test-framework | expected: post-Phase-3 commit; assert Vitest count equals post-Phase-1 count and `find scripts/__tests__ -name '*.test.ts'` returns empty
- [P0] `npm test` exits non-zero if Vitest passes but Bats fails — the `&&` chain must propagate Bats's exit status (FR-8) | mode: test-framework | expected: stub a failing Bats file; assert `npm test` exit code 1 with Vitest output present
- [P0] `npm test` exits non-zero if Bats passes but Vitest fails — symmetric chain check | mode: test-framework | expected: stub a failing Vitest file; assert exit 1 and Bats not invoked (short-circuit) OR invoked with first failure surfaced
- [P1] Pre-commit hook chain order is `lint-staged -> lint -> format:check -> test -> audit -> validate` — `validate` must run **after** `test` so test failures gate the layout check | mode: exploratory | expected: simulated pre-commit run with planted failures at each stage; document order via `.husky/pre-commit` inspection
- [P1] Husky pre-commit chain blocks commit when validator fires — committing a misplaced test file does not bypass via `--no-verify` accidentally | mode: exploratory | expected: stage a misplaced `.test.ts`, attempt `git commit`; confirm rejection with validator output
- [P1] Phase-2 sed rewrite that misses a non-standard `${BATS_TEST_DIRNAME}` expression form fails fast at `bats tests/bats` | mode: test-framework | expected: introduce a synthetic `${BATS_TEST_DIRNAME}/../helper-x` form before sed; confirm bats discovery surfaces the broken path
- [P1] Validator short-circuit — non-test extensions (`.ts`, `.md`, `.json`) walk through `classifyPath` returning `null` and don't generate FAIL lines | mode: test-framework | expected: walk a tree of 1000 non-test files; assert validator stdout is the trailing `0 violations` only
- [P2] Concurrent `npm test` and `npm run validate` invocations on the same checkout produce stable, independent results (no shared mutable state) | mode: exploratory | expected: run both in parallel terminals; assert each completes with its own exit code

### Environment

- [P0] Fresh checkout (no `node_modules`) — `npm test` fails with a clear message before any test runs because `bats` devDep is missing; user must `npm install` first | mode: exploratory | expected: clone -> `npm test`; document the error surface (`npx bats: not found` vs `script not found`) and confirm it isn't silently skipped
- [P0] After `npm install`, `npx bats --version` resolves and reports a 1.x version inside the caret range | mode: test-framework | expected: invoke `npx bats --version` in CI fixture; parse version and assert `1.x`
- [P0] `tests/fixtures/qa-fixture/` is reachable from the moved harness files (`tests/unit/qa-integration.test.ts`, `tests/unit/qa-dependency-failure-BUG-012.test.ts`, `tests/unit/qa-inputs-BUG-012.test.ts`) — relative path resolution survives the move (Edge Case 3) | mode: test-framework | expected: run those three Vitest files post-Phase-1; assert pass
- [P1] `feat-030-known-buggy` fixture's `vitest.config.ts` child-process invocation still resolves from its stay-in-place location after the migration (FR-2 exception honored) | mode: test-framework | expected: run `feat-030-executing-qa.test.ts`; assert it can spawn the child process and return results
- [P1] Bats path rewrites are independent of OS path separator — `BATS_TEST_DIRNAME` resolves identically on macOS and Linux | mode: exploratory | expected: smoke-test a sample skill's bats files on both platforms; assert pass
- [P1] Case-sensitive vs case-insensitive filesystem — paths like `tests/Unit/foo.test.ts` (capital U) are NOT silently accepted by the validator on macOS APFS (case-insensitive) when the canonical leaf is `tests/unit/` | mode: exploratory | expected: synthetic case-mismatched path; assert validator either fires `ts-outside-tests-unit` or document the platform behavior
- [P1] `tsconfig.test.json` extends base correctly — ESLint type-aware rules on test files don't fail with `rootDir: "./scripts"` collision (Phase 3 risk-table item) | mode: test-framework | expected: run `npm run lint` post-Phase-3; assert zero parser errors on `tests/**/*.ts`
- [P1] Vitest `coverage.exclude` honors `tests/**` so coverage reports don't double-count test files as covered code | mode: test-framework | expected: run `npm run test:coverage`; assert coverage report excludes `tests/**`
- [P2] CI environment (Linux) runs the full suite (Vitest + Bats) in under 2x the pre-feature Vitest-only runtime (NFR-4) | mode: exploratory | expected: capture pre-/post-feature CI runtime; document delta in PR body
- [P2] `.husky/pre-commit` latency stays acceptable for small commits — validator walk over `scripts/`, `plugins/`, `tests/` completes in <2s on this repo size (Phase 4 risk-table item) | mode: exploratory | expected: time `npm run validate` cold; document seconds in PR body
- [P2] `find` command on the plugin-install path tolerates mounts where `find -type f \( -name ... \)` syntax differs (BSD `find` on macOS vs GNU `find` on Linux) — both must report empty | mode: exploratory | expected: run FR-12 verification on macOS and Linux; assert both report empty

### Dependency failure

- [P0] `bats` npm package is the wrapper that surfaces a working CLI — if the install resolves to a 0-byte or broken bin, `npm test:bats` errors clearly rather than reporting "0 tests, all pass" | mode: exploratory | expected: temporarily corrupt `node_modules/.bin/bats` symlink; run `npm test`; confirm non-zero exit and visible error
- [P0] `tsx` failure compiling `scripts/validate-test-layout.ts` exits non-zero so `npm run validate` short-circuits with a visible error (not a silent skip) | mode: test-framework | expected: introduce a syntax error temporarily; assert `npm run validate` exit non-zero and stderr names the file/line
- [P0] PreToolUse hook command resolution — `tsx scripts/hooks/validate-test-layout-hook.ts` must work from any CWD because Claude Code may invoke the hook from arbitrary working directories | mode: exploratory | expected: invoke hook from a subdirectory CWD; assert correct behavior
- [P1] `gh pr view` failure during contributor docs (FR-7) — the npm-package install path documentation does not depend on `gh`; it depends only on `npx bats` resolving | mode: exploratory | expected: with no GitHub auth, run the `npx bats tests/bats` command from the docs; assert it works
- [P1] Bats version pinned at `^1.10.0` — a future major bump to 2.x is **not** silently picked up | mode: test-framework | expected: parse `package.json` `devDependencies.bats`; assert caret-1.x range
- [P1] Husky pre-commit failure modes — `lint-staged` failure, then `lint` failure, then `format:check` failure, then `test` failure, then `audit` failure, then `validate` failure — each stage's failure produces a distinct, identifiable message | mode: exploratory | expected: simulate failure at each stage; document the stage label in the user-facing output
- [P1] ESLint parser error when both tsconfigs are referenced — confirm `parserOptions.project: ['./tsconfig.json', './tsconfig.test.json']` resolves files in either tree without a "file not in any project" error | mode: test-framework | expected: lint a `tests/**/*.ts` file and a `scripts/**/*.ts` file; both must lint clean
- [P2] `/plugin install` from the marketplace — fresh install fetches `plugins/lwndev-sdlc/` source and `find <install-path> -type f \( -name '*.bats' -o -name '*.test.ts' -o -name '*.spec.ts' \)` returns empty (FR-12) | mode: exploratory | expected: install against fresh `CLAUDE_CONFIG_DIR`; run the find; assert empty and capture before/after `du -sh` (NFR-5)
- [P2] Plugin marketplace `source` path remains `./plugins/lwndev-sdlc` (no marketplace.json edit needed per Edge Case 7) — Phase 6 verifies via diff inspection | mode: exploratory | expected: inspect `.claude-plugin/marketplace.json` post-feature; assert source path unchanged

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] Hook reuses the SAME rule module as the validator (Edge Case 5) — both `scripts/validate-test-layout.ts` and `scripts/hooks/validate-test-layout-hook.ts` import `classifyPath` and `ALLOWED_FIXTURE_PATHS` from `scripts/test-layout-rules.ts` | mode: test-framework | expected: AST or grep assertion on import statements in both files; assert single source of truth
- [P0] Validator and hook agree on the allow-rule for `feat-030-known-buggy` — passing the same path through both produces the same verdict | mode: test-framework | expected: programmatically invoke both with the fixture path; assert validator returns no violation and hook exits 0
- [P1] Validator and hook agree on the rule ID strings — `ts-outside-tests-unit`, `spec-extension-disallowed`, `bats-outside-tests-bats` — emitted output uses the constants from the shared module, not hardcoded strings | mode: test-framework | expected: grep both implementations for the literal rule strings; assert no hardcoded duplication
- [P1] Read-only filesystem under `scripts/` or `plugins/` — validator must surface the read error rather than silently exiting 0 | mode: exploratory | expected: chmod -R 000 a subdirectory, run validator; assert non-zero exit and clear stderr
- [P1] Permission denied on `.husky/pre-commit` — git commit error is clear and points at the hook file | mode: exploratory | expected: chmod -x `.husky/pre-commit`; attempt commit; document the error surface
- [P2] Concurrent test invocations — running `npm test:unit` and `npm test:bats` in parallel produces stable, independent results (Vitest test isolation already covers this; Bats files are independent .bats invocations) | mode: exploratory | expected: launch both concurrently; assert each completes with its own exit code
- [P2] Symlinked test directories — if a contributor symlinks `tests/unit/old-tests` to `scripts/__tests__/`, the validator follows or rejects per a documented contract | mode: exploratory | expected: create symlink; document validator behavior in PR body
- [P2] PreToolUse hook does not block legitimate fixture edits — editing files inside `scripts/__tests__/fixtures/feat-030-known-buggy/` (the allow-rule fixture) does not fire the hook | mode: test-framework | expected: feed hook a `Write` tool_input for the allow-rule path; assert exit 0
- [P2] Hook output is suitable for the model to self-correct — rejection message names the rule and a canonical destination so the next attempt lands at `tests/unit/` or `tests/bats/` automatically | mode: exploratory | expected: inspect rejection message format; assert it contains both the rule name and a canonical-destination directory

## Non-applicable dimensions

- a11y: this feature has no UI surface — it is a build-time validator and a CLI hook. Keyboard navigation, screen-reader, and color-contrast scenarios do not apply.
- i18n locale formatting: there is no user-visible date/time/number/pluralization output; the only Unicode concern is file-path encoding (covered under Inputs).
- Authentication / authorization tokens: validator and hook operate on the local filesystem and do not consume tokens. No authz scope.
- Database state: feature touches no database. State is filesystem-only and covered under State transitions.
- Network/HTTP API: no network-bound surface. The only network-adjacent concern is `npm install` for the `bats` devDep and `/plugin install` for payload verification (covered under Dependency failure).
