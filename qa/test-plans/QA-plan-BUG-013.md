---
id: BUG-013
version: 2
timestamp: 2026-04-25T13:20:00Z
persona: qa
---

## User Summary

Phase-completion skills (`executing-chores`, `executing-bug-fixes`, `implementing-plan-phases`, `executing-qa`, `finalizing-workflow`, `releasing-plugins`) currently declare success without running the repo's lint/format/test commands, so prettier/eslint violations reach release branches and `main`. This change introduces a shared `verify-build-health.sh` script that detects available `package.json` scripts (`lint`, `format:check`, `test`, `build`; `validate` opt-in via `--include-validate`), runs each that exists, and halts with a non-zero exit on the first failure. Interactive call sites (`executing-chores`, `executing-bug-fixes`, `implementing-plan-phases`, `releasing-plugins`) offer an opt-in auto-fix path (`lint:fix`, `format`) before re-running; non-interactive call sites (`executing-qa`, `finalizing-workflow`, or any non-TTY invocation) fail-fast without prompting. Projects without a recognized `package.json` skip cleanly with an `[info]` log line.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Scenarios (by dimension)

### Inputs

- [P0] `package.json` missing entirely from the repo root | mode: test-framework | expected: bats test invokes the script in a tmp dir with no `package.json`; asserts exit 0, stdout/stderr contains `[info]` skip line, no npm spawn
- [P0] `package.json` present but has none of `lint`/`format:check`/`test`/`build` | mode: test-framework | expected: bats test creates a stub `package.json` with only unrelated scripts; asserts exit 0 and `[info]` skip line; no command attempted
- [P0] `package.json` is malformed JSON (truncated, trailing comma, mixed tabs) | mode: test-framework | expected: bats test feeds invalid JSON; asserts exit non-zero with a clear `[error]` line referencing the parse failure rather than a silent pass
- [P0] `package.json` declares `lint` but the command points to a missing binary (e.g. `eslint` not installed) | mode: test-framework | expected: bats test stubs a `lint` script invoking a nonexistent command; asserts the script exits non-zero, surfaces npm's own error verbatim, and does NOT proceed to `format:check`/`test`
- [P1] Script names with unusual characters (`lint:fix`, `test:unit`, `format:check:ci`) collide with the detector's prefix matching | mode: test-framework | expected: bats test verifies the detector matches `lint`/`format:check`/`test`/`build` exactly and does not erroneously invoke `lint:fix`/`test:unit` as if they were the canonical scripts
- [P1] Hidden `validate` script present but `--include-validate` not passed | mode: test-framework | expected: bats asserts `validate` is NOT invoked (per the opt-in AC); contrasted with a sibling case that does pass `--include-validate` and DOES invoke it
- [P1] Symlinked `package.json` (resolving outside the cwd) | mode: test-framework | expected: bats test creates a symlinked `package.json`; asserts the script resolves and runs the linked file's scripts, not a stale cwd copy
- [P2] Monorepo with multiple `package.json` files (root + per-package) | mode: exploratory | expected: manual verification that the script runs against the cwd's `package.json` only, not a parent-traversal hit; document the chosen behavior

### State transitions

- [P0] User Ctrl-C mid-`npm run lint` from the interactive auto-fix prompt | mode: exploratory | expected: manual repro: run a slow lint that the user interrupts; assert the script exits with a non-zero code, leaves no `.husky` or temp artifacts, and the orchestrator surfaces the abort to the user
- [P0] Auto-fix consents (yes), `lint:fix` runs, then the user Ctrl-Cs before the re-run completes | mode: exploratory | expected: manual repro: confirm auto-fix, abort during fix; assert the script exits non-zero and the partially-modified files are NOT silently committed by any downstream skill
- [P1] Two skills invoke the shared script concurrently (e.g., `implementing-plan-phases` mid-phase + a parallel `releasing-plugins` run) | mode: test-framework | expected: bats test spawns two concurrent invocations against the same repo; asserts both run to completion deterministically, no race on shared lockfiles or `node_modules`, neither corrupts the other's exit code
- [P1] Re-running after a partial auto-fix where another process modified files between the fix and the re-run | mode: exploratory | expected: manual repro: trigger auto-fix, edit a file mid-flight, observe the re-run; assert the re-run reports the new violation rather than reporting clean
- [P2] Auto-fix offered, user declines, then the script's own re-run logic re-prompts | mode: test-framework | expected: bats test simulates `n` to the auto-fix prompt; asserts the script exits non-zero immediately and does NOT re-prompt or re-run

### Environment

- [P0] Invoked from a non-TTY (orchestrator-forked subagent or CI) without `--no-interactive` | mode: test-framework | expected: bats test redirects stdin from `/dev/null`; asserts the script auto-detects non-TTY and behaves as if `--no-interactive` were passed (fail-fast, no prompt) per the AC
- [P0] `npm` not on `PATH` | mode: test-framework | expected: bats test runs the script with a `PATH` that excludes npm; asserts the script exits zero with an `[info]` skip line per the graceful-skip AC
- [P1] `node_modules` missing (cold checkout, no install) | mode: exploratory | expected: manual: clone fresh, run a workflow phase, observe behavior; assert the script either auto-installs (if that's the policy) or fails with a clear `[error]` pointing the user at `npm install`
- [P1] Read-only filesystem (e.g., container with read-only mount) | mode: exploratory | expected: manual: run on a read-only mount; assert auto-fix prompt is suppressed (cannot write) and the script reports the constraint rather than offering a fix that would silently fail
- [P1] `LANG`/`LC_ALL` set to a non-UTF-8 locale | mode: test-framework | expected: bats test sets `LANG=C`; asserts script output remains parseable (no mojibake in `[info]`/`[warn]`/`[error]` tagged lines, since the orchestrator parses these structurally)
- [P2] Clock skew or non-UTC timezone affects log timestamps | mode: exploratory | expected: spot-check: confirm the script does not embed timestamps in load-bearing output; if it does, document the format

### Dependency failure

- [P0] `eslint` binary present but crashes mid-run (segfault, OOM) | mode: exploratory | expected: manual: stub a crashing eslint; assert the script reports the crash exit code, does NOT proceed to subsequent checks, and does NOT swallow the failure
- [P0] `prettier` reports a parser error on a non-source file (e.g., binary file accidentally included) | mode: test-framework | expected: bats test seeds a binary file in the lint scope; asserts the script surfaces prettier's error verbatim and exits non-zero
- [P1] `husky` pre-commit hook runs the same checks during `git commit` later in the workflow | mode: exploratory | expected: manual: confirm both gates fire and that double-running is acceptable (no idempotency violation), or document overlap if the team decides to coordinate
- [P1] `npm` runs but `package-lock.json` is out of sync, causing a soft warning to stderr | mode: test-framework | expected: bats asserts a stderr warning does NOT cause the script to exit non-zero; only an actual command failure halts
- [P2] Network outage during a script that itself fetches remote rules (e.g., `eslint-config-*` from a registry mirror) | mode: exploratory | expected: manual: simulate network down; assert the failure is attributed correctly (network vs. lint logic) in the script's surfaced error

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] Two orchestrator workflows run concurrently against the same repo and both reach a build-health gate | mode: test-framework | expected: bats simulates concurrent invocations targeting overlapping files; asserts no shared-state corruption (lockfile race, stale cache hits, conflicting auto-fix writes)
- [P1] Permissions: script invoked under a user without write access to source files but auto-fix is requested | mode: exploratory | expected: manual: drop write perms on a target file, accept auto-fix; assert the script reports the permission error rather than silently falling back to a no-op
- [P1] Bats coverage itself fails on systems without `bats-core` installed | mode: exploratory | expected: manual: run `npm test` on a fresh checkout; assert the test suite either auto-installs bats or skips with a clear message rather than reporting a false pass
- [P2] i18n: error messages from npm/eslint surface in the user's locale; the orchestrator's parser expects English | mode: exploratory | expected: spot-check with `LANG=de_DE.UTF-8`; document any parser fragility against localized npm output
- [P2] Permission to add the new script under `plugins/lwndev-sdlc/scripts/` requires the marketplace plugin path to remain stable | mode: exploratory | expected: confirm the chosen path matches the conventions in `scripts/lib/constants.ts` (`getPluginDir`, `getPluginManifestDir`) so consumer installs pick the script up correctly

## Non-applicable dimensions

(None — every dimension applies to a build-health gate that runs across all six skills, all package-manager environments, and both interactive and non-interactive call sites.)
