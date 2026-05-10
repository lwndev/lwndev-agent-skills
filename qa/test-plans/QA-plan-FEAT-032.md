---
id: FEAT-032
version: 2
timestamp: 2026-05-09T16:59:43Z
persona: qa
---

## User Summary

When `executing-qa` returns an `ISSUES-FOUND` verdict, the orchestrator invokes a developer-persona fix skill. That skill reproduces the failure locally, fixes the production code, re-validates against the failing scenario, and adopts the ephemeral `qa-*` test into the regression suite. The intent is that adversarial knowledge becomes a permanent test, the production bug is fixed in the same PR, and no `qa-*` prefixed files leak past merge.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

```json
{
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript"
}
```

## Scenarios (by dimension)

### Inputs

- [P0] QA results artifact has verdict ISSUES-FOUND but the failed-test list is empty or absent | mode: test-framework | expected: fix skill exits with structured error naming the missing field; orchestrator surfaces it; no fix attempted
- [P0] QA results reference a `qa-*` test file path that does not exist on disk (manually deleted between QA run and fix invocation) | mode: test-framework | expected: fix skill aborts with a path-not-found error; no rename or commit occurs
- [P0] Failed test name contains shell-special characters (`$`, backticks, `;`, spaces) — adoption rename must not invoke the shell unsafely | mode: test-framework | expected: rename succeeds via filesystem API; no command injection; resulting filename matches the sanitized form
- [P1] Adopted test target name collides with an existing non-qa test in the same directory (e.g., `tests/unit/foo.test.ts` already exists) | mode: test-framework | expected: fix skill refuses to overwrite; surfaces a collision error and proposes a numbered suffix or aborts
- [P1] QA results artifact omits the `version: 2` frontmatter field (legacy v1 format) | mode: test-framework | expected: fix skill rejects with a clear "v2 required" message; orchestrator does not advance
- [P1] Test description contains non-ASCII / RTL / combining characters — adoption preserves the description but produces an ASCII-safe filename | mode: test-framework | expected: filename is normalized; in-file `describe`/`it` text is preserved verbatim
- [P2] QA results path resolves outside the repo root via `..` traversal (e.g., `qa-../../etc/foo.test.ts`) | mode: test-framework | expected: fix skill rejects the path; no write occurs outside the repo

### State transitions

- [P0] User cancels (Ctrl+C / closes session) after fix is written but before adoption rename | mode: exploratory | expected: on resume, orchestrator detects partial state — either re-runs adoption idempotently or surfaces a clear "incomplete fix" error; no `qa-*` file silently merges
- [P0] Re-validation passes but adoption rename fails (e.g., target directory missing) — production fix lands without test adoption | mode: test-framework | expected: orchestrator rolls back the fix commit OR halts before PR merge; constraint "no qa-* files past merge" is enforced
- [P1] Re-running the orchestrator after a successful fix-and-adopt cycle | mode: test-framework | expected: idempotent — orchestrator does not re-trigger fix skill; QA verdict on re-run is PASS
- [P1] Concurrent invocation: fix skill is already in-flight (active-marker exists) when orchestrator tries to spawn another | mode: test-framework | expected: second invocation is rejected or queued; no duplicate edits
- [P1] Re-validation passes locally but stop-hook / lint hook fails on commit | mode: test-framework | expected: fix skill surfaces hook failure; does not bypass with `--no-verify`; orchestrator pauses for user
- [P2] Fix produces an empty diff against main (no-op fix, e.g., the bug was a flaky test) | mode: test-framework | expected: orchestrator rejects the no-op fix; surfaces a "nothing to commit" error and pauses

### Environment

- [P0] Repo has no test framework detected (capability mode `exploratory-only`) | mode: test-framework | expected: fix skill aborts cleanly with a "test framework required for fix workflow" error; orchestrator does not crash
- [P1] Repo has both Jest and Vitest configs and capability discovery picks the wrong one for this test file | mode: exploratory | expected: re-validation runs against the correct framework for the failing test (matched by file extension or directory), not the repo-wide default
- [P1] Branch has uncommitted changes when the fix skill starts | mode: test-framework | expected: skill refuses to start with a "working tree not clean" error; does not silently `git stash`
- [P2] Disk full mid-write of the renamed adopted test file | mode: exploratory | expected: write fails atomically; original `qa-*` file is preserved; user receives a clear ENOSPC error
- [P2] Read-only filesystem under `tests/` (e.g., mounted volume) — adoption rename fails | mode: exploratory | expected: skill aborts with EACCES; original file untouched

### Dependency failure

- [P0] `npm test` (or detected test command) hangs indefinitely on the failing scenario during reproduction | mode: test-framework | expected: fix skill enforces a timeout; aborts with "reproduction step exceeded timeout"; no partial commit
- [P1] `gh pr view` returns 429 rate-limit during PR-context lookup | mode: test-framework | expected: skill retries with backoff or proceeds without PR context (degraded mode); does not crash
- [P1] `git mv` fails because target name differs only in case on a case-insensitive filesystem (macOS APFS default) | mode: exploratory | expected: skill detects the case collision; uses two-step rename or aborts with a specific error
- [P1] Detected test command exits non-zero for an unrelated flaky test, not the QA test under repair | mode: test-framework | expected: skill scopes re-validation to the specific failing test (e.g., `npm test -- -t "<test name>"`); does not misclassify unrelated failures as fix-needed
- [P2] Fix-skill SKILL.md cannot be read (permission denied or missing) | mode: test-framework | expected: orchestrator surfaces "skill not found" with the expected path; calls `fail`; does not silently advance

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] Concurrency: two phases of a feature workflow each emit ISSUES-FOUND in rapid succession — fix skill is invoked twice, racing on the same `qa-*` rename target | mode: exploratory | expected: orchestrator serializes fix-skill invocations per workflow ID; no race on filesystem renames
- [P1] Permissions: fix skill's adoption target directory is outside the configured test glob (e.g., the framework only collects `tests/unit/**`, but the renamed file lands under `tests/qa-adopted/`) — adopted test never runs | mode: test-framework | expected: skill writes to a directory the framework already discovers; verifies post-rename via a smoke run
- [P1] Permissions: fix skill must not gain authority to modify files outside `tests/` and the production module under repair (no scope creep) | mode: exploratory | expected: skill's edits are scoped; orchestrator audit confirms no unrelated diffs
- [P2] i18n: failing test name contains non-ASCII identifiers; the adopted file's `describe()` / `it()` strings are preserved bit-for-bit | mode: test-framework | expected: file content matches input encoding; no mojibake on round-trip read

## Non-applicable dimensions

- a11y (within Cross-cutting): this feature is a CLI orchestration workflow with no user-facing UI surface, screen reader, or visual layout; accessibility scenarios do not apply.
