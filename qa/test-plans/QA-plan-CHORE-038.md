---
id: CHORE-038
version: 2
timestamp: 2026-05-09T20:42:00Z
persona: qa
---

## User Summary

Flips Vitest's `fileParallelism: false` to `true` to cut unit-test wall time roughly 4.4x (58.5s -> 13.5s on the reference machine). Three test files that mutate the real `plugins/` tree (`scaffold.test.ts`, `validate-test-layout.test.ts`, `build.test.ts`) are isolated via `mkdtemp` or `describe.sequential` so concurrent runs stay deterministic. The `CLAUDE.md` Key Patterns note is updated to describe the new isolation strategy.

## Capability Report

```json
{
  "id": "CHORE-038",
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
- [P1] A new test file added later that writes to the real `plugins/` tree without isolation should fail under parallel mode rather than silently corrupting state | mode: exploratory | expected: documented isolation contract or lint/check that catches missing `mkdtemp`/`describe.sequential` for new tests writing under `plugins/`
- [P2] Test files referencing `PLUGINS_DIR` for read-only path lookups (29+ files) should remain unaffected by the parallelism flip | mode: test-framework | expected: full `npm run test:unit` pass count unchanged from sequential baseline

### State transitions
- [P0] Two parallel tests that both write into `plugins/lwndev-sdlc/skills/` race and corrupt each other's fixtures (the exact regression `fileParallelism: false` was added to prevent) | mode: test-framework | expected: 10 consecutive `npm run test:unit` runs produce identical pass/fail counts; failures stay at the documented baseline
- [P0] A test file leaves a fixture behind under `plugins/lwndev-sdlc/skills/` after a crash; subsequent parallel runs read stale state | mode: test-framework | expected: isolated tests use `mkdtemp` (auto-cleanup on process exit) rather than `plugins/` paths, so a crashed run leaves no residue
- [P1] `validate-test-layout.test.ts` already uses `mkdtemp` per the standard-review finding [W1]; if the implementer "isolates" it again with redundant changes, the suite should still pass | mode: test-framework | expected: file remains green; no double-isolation regressions
- [P1] A test depends on cwd being the repo root and another parallel test changes cwd mid-flight | mode: exploratory | expected: audit for `process.chdir` or relative-path assumptions in the 3 mutating tests

### Environment
- [P0] Slow CI runner exceeds the 20s wall-time threshold even though local runs hit 13.5s | mode: exploratory | expected: AC-3 measurement methodology documented (which environment, headroom rationale) or threshold tuned upward for CI
- [P1] Disk-full mid-parallel-write leaves partial fixtures in `plugins/`; sequential mode previously hid this | mode: exploratory | expected: error surfaces cleanly with the offending test name; no half-written files corrupt the tree
- [P1] Tests that read environment variables (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_SKILL_DIR`) under parallelism should not interfere with each other | mode: test-framework | expected: env-var setting via `vi.stubEnv` or per-test scope, not `process.env =` mutation
- [P2] `npm run test:watch` (same Vitest config) inherits the parallelism flip; watching a single file should not regress responsiveness | mode: exploratory | expected: watch-mode wall time on a single edit cycle stays comparable to or better than sequential

### Dependency failure
- [P1] `tsx` cold-start contention under parallelism — multiple `execSync('tsx scripts/release.ts ...')` invocations across files compete for CPU and may exceed the bumped 15s `testTimeout` | mode: test-framework | expected: full `npm run test:unit` completes within `testTimeout`; no `Test timed out` lines added vs sequential baseline
- [P2] Bats suite (`tests/bats/**`) is unaffected by Vitest config but still runs in `npm test`; verify the combined `npm test` script doesn't regress | mode: test-framework | expected: `npm test` completes faster than the prior ~92s with no new failures

### Cross-cutting (a11y, i18n, concurrency, permissions)
- [P0] Concurrency: the 3 mutating tests now run alongside ~50 other files; any shared mutable state (singletons in `scripts/lib/`, module-level caches) becomes flake-prone | mode: exploratory | expected: audit `scripts/lib/` for module-level mutable state; document or guard any singletons that tests touch
- [P1] Permissions: `mkdtemp` paths inherit OS temp-dir permissions; if any code under test asserts `0o755` or specific ownership, parallel temp dirs may differ from `plugins/` | mode: test-framework | expected: no test assertions on absolute paths or fixed ownership for fixture roots
- [P2] CLAUDE.md update is documentation-only; verify the new note is grep-able by tooling and matches the actual config (`fileParallelism: true`) | mode: test-framework | expected: `CLAUDE.md` Key Patterns section no longer asserts "tests run sequentially"

## Non-applicable dimensions

- a11y: this change affects test-runner configuration only; no UI surface, no user-facing accessibility concerns.
- i18n: no user-facing strings, dates, or locale-sensitive logic introduced; test runner is locale-agnostic.
- Injection / SQL / XSS / path-traversal: scope is internal Vitest config and test-file isolation; no untrusted input is introduced or processed.
