---
id: BUG-016
version: 2
timestamp: 2026-05-03T16:15:00Z
persona: qa
---

## User Summary

CHORE-037 added a 15th `.bats` file to `tests/bats/shared/`, breaking the 1:1 parity assertion in `tests/unit/shared-scripts.test.ts:106` between canonical shared scripts (14 entries) and bats fixtures. `main` has been red since the merge of PR #259 and every downstream PR is failing. The fix relocates the QA fixture from `tests/bats/shared/qa-CHORE-037-husky-hooks.bats` to `tests/bats/qa/qa-CHORE-037-husky-hooks.bats`, restoring the parity invariant. The relocated fixture must remain executable under `npm run test:bats` (which globs `tests/bats/**/*.bats` recursively).

## Capability Report

```json
{
  "id": "BUG-016",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript"
}
```

## Scenarios (by dimension)

### Inputs

- [P0] After the move, `tests/bats/shared/` contains exactly 14 `.bats` files (one per `CANONICAL_SCRIPTS` entry). | mode: test-framework | expected: vitest assertion at `tests/unit/shared-scripts.test.ts:106` passes; `readdirSync(TESTS_DIR).filter(f => f.endsWith('.bats')).length === 14`
- [P0] The relocated file `tests/bats/qa/qa-CHORE-037-husky-hooks.bats` exists and has byte-for-byte identical content to the pre-move file. | mode: test-framework | expected: vitest test reads both pre-move snapshot (commit `361002b`) and current `tests/bats/qa/...`; SHA-256 hashes match
- [P0] The pre-move path `tests/bats/shared/qa-CHORE-037-husky-hooks.bats` no longer exists. | mode: test-framework | expected: `existsSync('tests/bats/shared/qa-CHORE-037-husky-hooks.bats') === false`
- [P1] No other `.bats` file under `tests/bats/shared/` was deleted, renamed, or modified during the move. | mode: test-framework | expected: every entry in `CANONICAL_SCRIPTS` still has its corresponding `tests/bats/shared/{name}.bats` fixture (per-entry `existsSync` loop)
- [P1] The 14 surviving `tests/bats/shared/*.bats` filenames each map 1:1 to a `CANONICAL_SCRIPTS` entry (no spurious files left behind). | mode: test-framework | expected: `Set(batsFiles)` equals `Set(CANONICAL_SCRIPTS.map(canonicalToFixtureName))`

### State transitions

- [P1] If `tests/bats/qa/` already exists (e.g., a teammate landed `tests/bats/qa/<other>.bats` first), the move does not silently overwrite an existing same-named target. | mode: exploratory | expected: `git mv` would fail with "destination exists"; manual reproduction by pre-creating the target then attempting the move
- [P2] Re-running `npm test` after the move is idempotent — back-to-back runs both green. | mode: test-framework | expected: invoking `npm test` twice in succession returns exit 0 both times with no flaky output

### Environment

- [P0] On a case-sensitive filesystem (Linux CI), the new path resolves correctly — `tests/bats/qa/` is lowercase and matches the package.json glob. | mode: test-framework | expected: GitHub Actions Ubuntu runner executes `npm run test:bats` and the relocated file is discovered (asserts via test output containing the filename)
- [P1] On a case-insensitive filesystem (macOS dev machine), no accidental case-collision against `tests/bats/QA/` or `tests/bats/Qa/`. | mode: exploratory | expected: `find tests/bats -type d -iname qa` returns exactly one entry, all-lowercase
- [P2] Layout validator at `scripts/test-layout-rules.ts` accepts `tests/bats/qa/qa-CHORE-037-husky-hooks.bats` as a valid path (no rejection because the new directory is unrecognized). | mode: test-framework | expected: layout-validator vitest test runs with the new file present and exits 0

### Dependency failure

- [P1] `npm run test:bats` recursive glob (`tests/bats/**/*.bats` per `package.json`) actually picks up `tests/bats/qa/qa-CHORE-037-husky-hooks.bats`. Confirms the relocation is not orphaned. | mode: test-framework | expected: `npx bats -r tests/bats --list` (or equivalent) emits the new path in stdout
- [P2] If `parallel` (GNU parallel for `--jobs 8`) is unavailable, the relocated fixture still runs serially via `npx bats tests/bats/qa/qa-CHORE-037-husky-hooks.bats`. | mode: exploratory | expected: direct `npx bats` invocation on the new path completes without error

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P1] The `tests/bats/qa/` directory is created (via `mkdir -p` or `git mv` auto-create) before the file is staged — the move does not stage a file under a non-existent directory. | mode: test-framework | expected: post-fix `git status` shows `tests/bats/qa/qa-CHORE-037-husky-hooks.bats` as a tracked addition under an existing directory; no "directory does not exist" git warning
- [P2] Pre-push hook (which runs the heavy test suite per CHORE-037) passes on the fix branch before the PR opens. | mode: exploratory | expected: developer attempts `git push` and the husky pre-push hook runs `npm test` (or its successor) green

## Non-applicable dimensions

- inputs (oversized payloads, malformed input, injection): the change is a pure file relocation with no runtime input surface, no new API, no new parser. There are no payloads to malform.
- state transitions (cancellation, double-click, network interruption): the change has no user-facing interactive surface and no in-flight transactional state. The "transition" is a one-shot file move at commit time.
- environment (offline / slow network / clock skew): no network calls, no time-sensitive logic, no caching. The fix is pure filesystem rearrangement evaluated at test-run time.
- dependency failure (external API 5xx, rate limiting): no external API or service involved; only local file paths and the bats CLI.
- cross-cutting (a11y, i18n): no UI surface, no localized strings, no accessibility tree. The change is purely structural in the test directory layout.
