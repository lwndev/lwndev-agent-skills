---
id: FEAT-026
version: 2
timestamp: 2026-04-23T01:15:23Z
persona: qa
---

## User Summary

Collapse deterministic prose in the `reviewing-requirements` skill into six skill-scoped shell scripts so every review invocation (standard, test-plan reconciliation, code-review reconciliation) replaces its reference-extraction, reference-verification, mode-detection, cross-ref-check, test-plan-reconciliation, and PR-diff-vs-plan prose with a single script call. Ships the six scripts plus bats tests, rewrites SKILL.md to point at the scripts, updates a handful of caller docs, and keeps the reasoning work (severity classification, gap analysis, auto-fix selection) in prose. The reasoning surface of the skill is unchanged; only the mechanical surface moves to scripts.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

Note: the unit-of-test for this feature is bash scripts, which are tested via bats (not vitest). The capability report reflects the consumer repo's toolchain; bats fixtures ship alongside each script under `scripts/tests/` per precedent (e.g., `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats`). Scenarios below use `mode: test-framework` for anything a bats fixture can directly express; anything requiring live `gh`, live filesystem race, or human-driven inspection is `mode: exploratory`.

## Scenarios (by dimension)

### Inputs

- [P0] Script invoked with zero positional args → exits 2 and emits a clear stderr message naming the missing arg | mode: test-framework | expected: bats assertion on exit code 2 and stderr substring per script
- [P0] `verify-references.sh` arg resolution: arg starting with `{` treated as JSON literal, arg not starting with `{` or `[` treated as file path, nonexistent file path fallback to treating arg as JSON string | mode: test-framework | expected: bats table-driven fixture covering the three branches of the documented dispatch heuristic
- [P0] `detect-review-mode.sh` with `--pr abc` (non-numeric) → exits 2 with the `[warn] detect-review-mode: --pr value must be numeric` line | mode: test-framework | expected: bats assertion on exit 2 and stderr substring
- [P0] `extract-references.sh` produces an output shape with all four arrays always present (empty arrays when no matches), not a shape that omits keys | mode: test-framework | expected: bats `jq -e '.filePaths, .identifiers, .crossRefs, .ghRefs'` assertion on an input with zero references
- [P1] `extract-references.sh` de-duplication: an input mentioning the same file path 10 times emits it once, preserving first-occurrence order | mode: test-framework | expected: bats fixture asserts array length and ordering
- [P1] Paths with spaces, unicode, or backticks in the requirement doc do not break `filePaths` extraction or cause command-injection when later passed to `git grep` / `git ls-files` | mode: test-framework | expected: bats fixture with adversarial filenames (`my file.md`, `résumé.md`, `$(rm -rf).md`); assert no shell expansion, no crash
- [P1] `extract-references.sh` does NOT misclassify reference-shaped tokens inside fenced code blocks (known existing behavior per Edge Case 12 — extractor does not distinguish; the test pins this so a future change does not silently break downstream callers) | mode: test-framework | expected: bats fixture with tokens in fenced blocks asserts they are extracted (regression lock, not a correctness claim)
- [P1] `detect-review-mode.sh` with malformed ID (`FEAT-`, `feat-026` lowercase, `FEAT026` no-hyphen, trailing whitespace) → exits 2 | mode: test-framework | expected: bats table-driven fixture of malformed IDs
- [P1] `reconcile-test-plan.sh` against a test plan with no `## Acceptance Criteria` in the requirements doc → exits 1 with actionable stderr | mode: test-framework | expected: bats fixture with minimal-req doc missing AC, assert exit 1
- [P1] `reconcile-test-plan.sh` against a test plan with zero parseable scenario lines → exits 1 | mode: test-framework | expected: bats fixture with empty-scenarios plan
- [P1] `pr-diff-vs-plan.sh` with a negative, zero, floating-point, or hex `<pr-number>` → exits 2 | mode: test-framework | expected: bats fixture of malformed PR numbers
- [P2] Excessively long requirement doc (≥ 10 MB) does not crash any script; either succeeds or fails cleanly with a stderr explanation | mode: exploratory | expected: manual synth of an oversized doc; observe each script's behavior and document memory / time
- [P2] Requirement doc containing a `FR-999999` reference that does not exist — extract returns it; cross-ref-check classifies as `missing` | mode: test-framework | expected: bats fixture
- [P2] Input JSON to `verify-references.sh` containing keys the script does not recognize (forward-compat) → script processes known keys and ignores unknowns without erroring | mode: test-framework | expected: bats fixture with extra `fooBar` key

### State transitions

- [P0] Each script is idempotent: identical input twice in a row produces identical stdout (relevant for pure scripts FR-1/FR-2/FR-3/FR-4; FR-5 and FR-6 also expected to be pure given fixed inputs) | mode: test-framework | expected: bats `run ... ; run ...; [ "$output_1" = "$output_2" ]`
- [P1] `detect-review-mode.sh` called while a git rebase / merge / cherry-pick is in progress (repo in partial state) → does not crash; falls through predictably | mode: exploratory | expected: manual setup: `git rebase -i HEAD~2`, abort mid-rebase; run detect-review-mode; document behavior
- [P1] Concurrent invocations of the same script on the same input from two terminals → no interference (scripts do not write shared state) | mode: exploratory | expected: background + foreground invocation with `diff` on outputs
- [P2] Script receives `SIGINT` mid-execution → exits without leaving tempfiles, partial artifacts, or stale active markers | mode: exploratory | expected: manual `Ctrl-C` during a long-running `verify-references.sh` on a large refs JSON; check `/tmp` for orphans

### Environment

- [P0] Scripts invoked with `cwd != repo root` (e.g., from a subdirectory) behave the same way: relative paths in input JSON / requirement docs resolve the same as when invoked from the repo root | mode: test-framework | expected: bats fixture that `cd`s into a subdir before invocation
- [P0] `jq` absent: if a script declares a `jq` dependency (per Dependencies section of FEAT-026), it emits a clear stderr and exits non-zero rather than producing malformed JSON | mode: exploratory | expected: `PATH=/usr/bin:/bin` (no brew jq) invocation; observe error
- [P0] `git` absent or binary unusable: scripts that shell out to `git ls-files` / `git grep` emit clear stderr and do not segfault | mode: exploratory | expected: rename `git` binary on PATH; observe `verify-references.sh` behavior
- [P1] Repo on case-insensitive filesystem (default macOS APFS) vs case-sensitive (Linux): `filePaths` verification (`git ls-files | grep -F`) does not falsely classify case-variant matches as `ok` on Linux | mode: exploratory | expected: run bats tests on both macOS and Linux CI; diff classifications on a fixture with `File.md` vs `file.md`
- [P1] Repo with zero commits yet (freshly-initialized) → `git ls-files` returns empty; `verify-references.sh` classifies every ref as `missing` without crashing | mode: test-framework | expected: bats fixture creates empty git repo, runs verify
- [P1] Repo with submodules: `git ls-files` does not recurse into submodules by default; `verify-references.sh` classifications of a submodule-owned file are consistent with the documented behavior (either `missing` because submodule content isn't in parent ls-files, or explicitly `unavailable` — FEAT-026 does not specify submodule handling, which is itself a latent gap) | mode: exploratory | expected: manual clone of the repo with a submodule; run verify-references on a ref inside the submodule; document behavior and flag as gap
- [P1] Repo with non-ASCII filenames (unicode paths) → `filePaths` extraction and verification preserve the exact byte sequence, no mojibake | mode: test-framework | expected: bats fixture with `résumé.md`
- [P2] Very deep path (`a/b/c/d/e/.../100-levels.md`) — verify-references handles without path-length crash | mode: test-framework | expected: bats fixture
- [P2] Read-only filesystem — scripts do not attempt to write and do not fail just because the CWD is read-only (they only emit to stdout/stderr) | mode: exploratory | expected: `chmod -w .` and run each script; confirm stdout still produced
- [P2] Scripts invoked under a locale that uses a non-C collation order (e.g., `LC_ALL=tr_TR.UTF-8` — Turkish dotless-i) → regex classifications for `ghRefs`, `crossRefs`, and `identifiers` do not break | mode: exploratory | expected: `LC_ALL=tr_TR.UTF-8 bash detect-review-mode.sh FEAT-026`; observe

### Dependency failure

- [P0] `gh` absent on PATH: `detect-review-mode.sh` falls through to test-plan check and then standard mode; `pr-diff-vs-plan.sh` emits `[warn]` and exits 0 with empty stdout; `verify-references.sh` classifies `ghRefs` as `unavailable` and emits `[info]` stderr line | mode: test-framework | expected: bats test that stubs `gh` to be missing; asserts each script's graceful-degradation contract per NFR-1
- [P0] `gh` present but unauthenticated (`gh auth status` returns non-zero): same behavior as `gh` absent for all three scripts | mode: test-framework | expected: bats test that stubs `gh auth` failure
- [P0] `gh issue view <N>` returns 404 (issue genuinely does not exist): `verify-references.sh` classifies as `missing`, NOT `unavailable`; the error path is distinct from the graceful-degradation path | mode: test-framework | expected: bats test with a stubbed gh that returns 404 for known-missing IDs
- [P1] `gh pr list --head <pattern>` returns an empty array: `detect-review-mode.sh` falls through to step 3 (test plan check), not an error | mode: test-framework | expected: bats test with stubbed `gh` returning `[]`
- [P1] `gh pr list --head <pattern>` returns a valid JSON array but first element lacks `number` field (edge case 7a): emits `[warn] detect-review-mode: gh response missing 'number' field; falling through.`; continues to next precedence step | mode: test-framework | expected: bats test with stubbed `gh` returning `[{"state":"OPEN"}]`
- [P1] `gh` rate-limited (5xx or 4xx-rate-limit response) mid-`verify-references` batch of `ghRefs`: ALL remaining ghRefs are classified `unavailable`, not a mix of `ok`/`unavailable` — the script does not keep retrying per-ref in a loop that blows past the rate-limit budget | mode: exploratory | expected: manual test against a real rate-limited gh token (or a stubbed 429 response); observe
- [P1] `gh` network timeout mid-call (TCP hang): scripts eventually give up within a bounded time (or the caller's wrapping timeout kills them cleanly) | mode: exploratory | expected: run verify-references with a stubbed `gh` that sleeps forever; confirm no hang longer than a documented ceiling
- [P1] `gh pr diff <N>` returns an empty diff (closed PR with no changes): `pr-diff-vs-plan.sh` emits empty-arrays shape and exits 0 | mode: test-framework | expected: bats test with stubbed `gh pr diff` returning empty string
- [P1] `gh pr diff <N>` returns a diff with binary-only changes (e.g., screenshot PR): `pr-diff-vs-plan.sh` emits empty `flaggedSignatures` and handles `flaggedFiles` best-effort (edge case 14) | mode: test-framework | expected: bats fixture with a binary-only diff
- [P2] `gh pr diff <N>` returns truncated output due to server-side size limit: script detects truncation (if gh signals it) or proceeds best-effort; does not emit plausible-but-wrong flagging from a partial diff | mode: exploratory | expected: manual synth of a massive PR; observe

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] **Self-bootstrapping regression**: the scripts being built are called by the `reviewing-requirements` skill that reviews this very feature's PR. If the PR's branch has scripts committed but SKILL.md still contains the pre-rewrite prose (mid-branch intermediate state), orchestrated `reviewing-requirements` invocations must still work — either via the old prose OR via the new scripts, not half-and-half. Phase 4 (SKILL.md rewrite) lands last by design; verify no earlier phase breaks the running skill. | mode: exploratory | expected: after Phase 1 commits land but before Phase 4, manually run `/reviewing-requirements FEAT-026` and confirm it still produces a coherent findings block
- [P0] **Orchestrator concurrency**: two orchestrator forks running `reviewing-requirements` on different IDs at the same time must not interfere — scripts write only to stdout/stderr and do not create shared tempfiles in predictable locations | mode: exploratory | expected: two background invocations with different `<ID>` args; `diff` outputs to ensure no cross-contamination
- [P1] **Permissions**: scripts invoked under an unprivileged user (not the repo owner) — `git` can still read the repo, scripts behave normally | mode: exploratory | expected: `sudo -u nobody bash verify-references.sh ...` in a test environment
- [P1] **i18n — identifier name with unicode**: a requirement doc referencing a backticked identifier containing non-ASCII characters (e.g., `` `validateΩ()` ``) — `identifiers` extraction regex either accepts it consistently or rejects it consistently; no undefined behavior | mode: test-framework | expected: bats fixture with an identifier containing a Greek letter; assert presence or absence in output is deterministic and documented
- [P1] **i18n — requirement doc with BOM or CRLF line endings** (authored on Windows): all scripts handle the file without extraction glitches | mode: test-framework | expected: bats fixture with a BOM-prefixed / CRLF-terminated doc
- [P2] **Concurrency — orchestrator re-run on findings**: Phase 3's `reconcile-test-plan.sh` called twice in quick succession on the same pair of docs (e.g., during a re-review after fix) must return identical output (idempotency) | mode: test-framework | expected: bats fixture, two invocations, diff
- [P2] **a11y**: N/A (covered under Non-applicable dimensions) | mode: N/A | expected: N/A

## Non-applicable dimensions

- a11y: this feature ships shell scripts consumed by the orchestrator. No UI surface, no human-readable output beyond structured logs meant for programmatic consumption. Accessibility testing has no surface to bind to here. Load-bearing `[info]` / `[warn]` stderr lines are the closest analogue to a human-facing channel, and their literal-string requirements are covered by the Dependency-failure and Input dimensions above (exact stderr strings asserted in bats).
