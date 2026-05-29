---
id: BUG-022
version: 2
timestamp: 2026-05-29T13:42:01Z
persona: qa
---

## User Summary

`executing-qa` must not falsely enter re-QA mode on the first QA run for a
fresh requirement ID. Before the fix, when committed `qa-*` test files existed
on the branch, re-QA detection returned `mode=re-qa` on an initial run — the
skill then skipped test authoring and ran unrelated prior-workflow tests,
yielding a misleading PASS. After the fix, an initial run for an ID with no
prior QA history resolves to `mode=initial` regardless of committed `qa-*`
files, while a genuine prior QA run for the same ID still resolves to `re-qa`.
The system under test is the shell detection contract (`detect-re-qa-mode.sh`
and its interaction with `qa-baseline.sh init`, committed `qa-*` files, and
the per-ID workflow state), exercised via Bats.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

> Note: capability discovery reports the repo's primary framework (vitest), but
> the code under QA is shell. Deterministic scenarios are expressed as Bats
> tests (`npx bats`, graded on exit code); they are tagged `mode: test-framework`.
> Tooling-absence and environment scenarios are `exploratory`.

## Scenarios (by dimension)

### Inputs
- [P0] Fresh ID (no prior QA history) with committed `qa-*.test.ts` present on the branch and the baseline marker freshly written by the current run -> resolves to `mode=initial` | mode: test-framework | expected: Bats asserts JSON `.mode == "initial"`, exit 0
- [P0] Genuine prior run for the same ID (prior fix attempt or recorded verdict) with committed `qa-*` files present -> resolves to `mode=re-qa` | mode: test-framework | expected: Bats asserts `.mode == "re-qa"` and `.files` non-empty, exit 0
- [P1] Committed `qa-*` files belong to an unrelated ID while the ID under test is fresh -> `mode=initial` (per-ID isolation, not branch-wide) | mode: test-framework | expected: Bats asserts `.mode == "initial"`
- [P1] Missing or empty ID argument -> usage error, exit 2 (existing contract preserved) | mode: test-framework | expected: Bats asserts non-zero exit and stderr usage line
- [P1] ID containing shell-special characters or a non-existent ID -> no crash; mode derived from state lookup | mode: test-framework | expected: Bats asserts exit 0 and valid JSON
- [P2] Baseline marker present but empty or malformed (non-SHA) contents -> decision keys on per-ID state, not marker contents | mode: test-framework | expected: Bats asserts `.mode == "initial"` for a fresh ID

### State transitions
- [P0] Same ID across two sequential runs: first run records QA history, second run flips `initial -> re-qa` given committed `qa-*` files | mode: test-framework | expected: Bats drives two invocations and asserts the mode transition
- [P1] Prior run recorded a verdict but zero fix attempts (e.g. an initial ERROR/EXPLORATORY-ONLY) -> subsequent run for the ID treated as a genuine prior run | mode: test-framework | expected: Bats asserts `.mode == "re-qa"` when only the verdict signal is set
- [P1] No workflow state file exists for the ID (manual `/executing-qa` outside an orchestrated workflow) -> deterministic, documented fallback (no false re-qa) | mode: test-framework | expected: Bats asserts a defined mode and exit 0 with no state file present

### Environment
- [P1] Invoked outside a git repository / `git` unavailable -> graceful degradation, no unhandled error | mode: test-framework | expected: Bats asserts exit 0 and `.files == []`
- [P2] Invoked from a subdirectory rather than the repo root -> `.sdlc/qa` and `tests/` path assumptions resolve correctly or fail cleanly | mode: exploratory | expected: manual run from a nested cwd; observe path resolution
- [P2] `jq` absent or a different version on PATH -> detection does not hard-crash with an opaque error | mode: exploratory | expected: manual run with `jq` shadowed; observe error clarity

### Dependency failure
- [P1] `workflow-state.sh get-qa-state` (or equivalent state read) returns non-zero or malformed JSON -> detection fails safe to `initial`, not `re-qa` | mode: test-framework | expected: Bats stubs a failing state read and asserts `.mode == "initial"`
- [P2] State file present but missing `qaFixAttempts` / `qaLastVerdict` fields (pre-FEAT-032 schema) -> defaults (0 / null) applied -> `initial` for a fresh ID | mode: test-framework | expected: Bats seeds a legacy-shaped state file and asserts `.mode == "initial"`

### Cross-cutting (a11y, i18n, concurrency, permissions)
- [P1] Idempotency: two back-to-back detect invocations for the same ID yield the same mode and never mutate the marker (read-only contract) | mode: test-framework | expected: Bats asserts identical output across runs and marker SHA unchanged
- [P2] Two different IDs on the same branch with committed `qa-*` files: a fresh ID stays `initial` while a prior-run ID resolves `re-qa` in the same tree | mode: test-framework | expected: Bats seeds divergent per-ID state and asserts each mode independently
- [P2] `qa-baseline.sh init` ordering: with `init` called before detect (current SKILL.md step order), a fresh ID still resolves `initial` -> the fix holds regardless of call-site ordering | mode: test-framework | expected: Bats reproduces the step-1-then-step-2 sequence and asserts `initial`

## Non-applicable dimensions

- a11y: the system under test is a CLI/shell detection script with no user interface surface; no accessibility behavior to probe.
- i18n: detection emits machine-readable JSON keyed on fixed ASCII tokens (`initial`/`re-qa`); no localized or user-facing natural-language output.
