---
id: FEAT-030
version: 2
timestamp: 2026-04-25T23:00:00Z
persona: qa
---

## User Summary

The executing-qa skill currently silently edits production code to make failing tests pass, hides bugs behind artificially green verdicts, and runs ~2,350-3,450 tokens of mechanical prose per workflow. This change consolidates three open issues (#187, #192, #208) into one feature: locks a return contract (artifact + final-message line + workflow-state findings shape), ships six producer scripts plus a coverage-verifier script that replaces the qa-verifier agent, adds a stop-hook diff guard that blocks edits outside the framework's test root, persists structured findings to workflow-state via a new `record-qa-findings` subcommand, wires the orchestrator to parse the contract and persist findings before advancing, and adds an explicit non-remediation rule to executing-qa SKILL.md.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Scenarios (by dimension)

### Inputs

- [P0] qa-reconcile-delta.sh receives a results doc with malformed frontmatter (missing closing ---) | mode: test-framework | expected: bats test asserts exit 2 with "unparseable frontmatter" on stderr; stdout empty
- [P0] qa-reconcile-delta.sh receives a requirements doc that is empty (zero bytes) | mode: test-framework | expected: bats test asserts exit 1 with empty-doc skip message; coverage-gap/coverage-surplus both 0
- [P0] qa-reconcile-delta.sh receives a binary file as input | mode: test-framework | expected: bats test asserts exit 1 with "not a markdown document" stderr; no segfault, no infinite loop
- [P0] run-framework.sh receives a capability JSON with unsupported framework (e.g., "rspec") | mode: test-framework | expected: bats test asserts exit 1 with "unsupported framework" stderr; no shell injection from JSON values
- [P0] run-framework.sh receives a test-file glob that matches zero files | mode: test-framework | expected: bats test asserts exit 1 with "no test files matched" stderr; framework not invoked
- [P0] render-qa-results.sh receives an unrecognized verdict value (e.g., "BROKEN") | mode: test-framework | expected: bats test asserts exit 1 with "invalid verdict" stderr; no artifact written
- [P0] render-qa-results.sh receives execution-json with negative counts (e.g., passed: -1) | mode: test-framework | expected: bats test asserts exit 1 with validation error; no artifact written
- [P0] capability-report-diff.sh receives JSON with unicode/emoji values in framework field | mode: test-framework | expected: bats test asserts UTF-8 round-trips through the diff output without corruption
- [P1] qa-verify-coverage.sh receives an artifact whose frontmatter has duplicate `verdict:` lines | mode: test-framework | expected: bats test asserts last-write-wins or explicit error - pinned by behavior, not unspecified
- [P1] commit-qa-tests.sh receives test-file paths containing spaces or shell metacharacters | mode: test-framework | expected: bats test asserts files are committed verbatim; no shell injection from filenames
- [P1] orchestrator parses a final-message line with extra whitespace ("Verdict:   ISSUES-FOUND  | Passed: 15") | mode: test-framework | expected: bats test asserts regex tolerates the whitespace OR explicitly rejects it - behavior is pinned
- [P1] orchestrator parses a final-message line where Verdict appears twice (once in mid-text, once at end) | mode: test-framework | expected: bats test asserts the LAST matching line wins (matches the existing Found N errors parser convention)
- [P2] check-branch-diff.sh runs in a detached-HEAD state | mode: test-framework | expected: bats test asserts exit 1 with helpful message naming the branch state
- [P2] qa-reconcile-delta.sh receives a results doc with FR-N references inside fenced code blocks | mode: test-framework | expected: bats test asserts FR-N references inside ``` blocks are NOT counted toward reconciliation matching

### State transitions

- [P0] executing-qa is invoked twice in the same session (re-run after fixing a test) | mode: test-framework | expected: bats test asserts the second run overwrites the previous artifact and re-records findings - workflow-state has only ONE QA findings block per step entry, not two
- [P0] stop-hook diff guard with `git status` showing a file modified BEFORE executing-qa started | mode: test-framework | expected: bats test asserts the pre-existing modification is NOT attributed to QA (uses session baseline, not whole-tree status); the guard only flags modifications since session start
- [P0] stop-hook diff guard fires DURING the run (between writing tests and running them) | mode: test-framework | expected: bats test asserts the guard only fires at Stop event time, not mid-run; iterative test-file authoring is not blocked
- [P0] orchestrator's record-qa-findings call fails (e.g., workflow JSON file deleted between QA run and orchestrator parse) | mode: test-framework | expected: bats test asserts orchestrator emits a `fail` and does NOT advance; QA artifact is preserved on disk
- [P1] qa-reconcile-delta.sh interrupted via SIGINT mid-parse | mode: exploratory | expected: manual: re-run produces same delta; no partial output written to disk
- [P1] commit-qa-tests.sh runs when there are staged changes that are NOT QA test files | mode: test-framework | expected: bats test asserts pre-existing staged files are preserved (not committed under the qa() prefix); only the named test files are added
- [P1] commit-qa-tests.sh runs when the test files are already committed | mode: test-framework | expected: bats test asserts exit 1 with "no files to commit" info message; workflow continues
- [P1] orchestrator parses a final-message line, then executing-qa is re-invoked - second invocation's findings overwrite first | mode: test-framework | expected: bats test asserts findings block is replaced, not appended; modelSelections audit-trail untouched
- [P2] qa-verify-coverage.sh runs against an artifact whose `## Reconciliation Delta` section was edited by hand between QA run and verify | mode: exploratory | expected: manual: verifier still classifies coverage adequacy from `## Scenarios Run`; reconciliation-delta drift is noted but not blocking

### Environment

- [P0] stop-hook diff guard runs in a worktree (not the main checkout) | mode: test-framework | expected: bats test asserts the guard inspects the correct worktree's status, not the main repo's
- [P0] stop-hook diff guard runs when `.git` is a file (submodule scenario) | mode: test-framework | expected: bats test asserts guard handles submodule layout without false-positive blocking
- [P1] run-framework.sh runs with a missing `node_modules` (npm install not run) | mode: test-framework | expected: bats test asserts the framework's own error is captured in execution JSON; verdict becomes ERROR; artifact written; no infinite retry
- [P1] run-framework.sh runs with insufficient disk space (write to test-results dir fails) | mode: exploratory | expected: manual: capability-report-diff and run-framework gracefully report write failure
- [P1] qa-reconcile-delta.sh runs against a 5,000+ line requirements doc | mode: test-framework | expected: bats test asserts completion under 2 seconds (NFR-2)
- [P1] orchestrator runs the QA step in a CI environment where `gh` is unavailable | mode: test-framework | expected: bats test asserts the QA step's record-qa-findings call does not depend on `gh`; only `jq` and `bash` required
- [P2] check-branch-diff.sh runs against a non-default base branch (e.g., `develop` instead of `main`) | mode: exploratory | expected: manual: behavior is pinned - either the script accepts a base-branch arg or it always assumes `main`; document the choice in FR-4

### Dependency failure

- [P0] workflow-state.sh `record-qa-findings` (or generalized `record-findings --type qa`) is called when the workflow JSON file is locked by another process | mode: test-framework | expected: bats test asserts atomic write semantics (move-on-write or flock); no partial JSON ever appears
- [P0] workflow-state.sh `record-qa-findings` is called with a stepIndex pointing to a non-QA step (e.g., reviewing-requirements) | mode: test-framework | expected: bats test asserts exit 1 with "step is not a QA step" stderr; no state mutation
- [P1] orchestrator's parse path runs against an executing-qa response missing the final-message line entirely | mode: test-framework | expected: bats test asserts contract-mismatch `fail` is emitted with actionable error; workflow halts at QA step
- [P1] qa-verify-coverage.sh runs against an artifact missing the `## Scenarios Run` section | mode: test-framework | expected: bats test asserts COVERAGE-GAPS verdict with the missing section listed as a gap
- [P1] qa-reconcile-delta.sh runs against a requirements doc with no `## Acceptance Criteria` section | mode: test-framework | expected: bats test asserts coverage-gap counts from FR/NFR alone; reconciliation continues
- [P1] commit-qa-tests.sh runs when `git config user.email` is unset | mode: test-framework | expected: bats test asserts the commit's pre-flight check fails with a helpful "git identity not configured" stderr; no orphan staged changes left behind
- [P2] capability-report-diff.sh runs when the plan's frontmatter capability block is in YAML flow style (single-line) vs block style | mode: test-framework | expected: bats test asserts both YAML styles parse correctly

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] qa-reconcile-delta.sh runs against a requirements doc containing CJK characters in FR descriptions | mode: test-framework | expected: bats test asserts UTF-8 is preserved end-to-end; reconciliation matching does not corrupt CJK text
- [P0] stop-hook diff guard handles file paths containing non-ASCII characters | mode: test-framework | expected: bats test asserts files like `tests/日本語_test.ts` inside the test root are correctly identified as test files
- [P0] orchestrator's parse path runs concurrently with another orchestrator instance for a different workflow ID | mode: test-framework | expected: bats test asserts no cross-contamination - findings record against the correct workflow JSON only
- [P1] qa-verify-coverage.sh runs against an artifact created on Windows (CRLF line endings) | mode: test-framework | expected: bats test asserts CRLF and LF artifacts produce identical verdict
- [P1] commit-qa-tests.sh runs when the user's git config has signing enabled (commit.gpgsign=true) and the key is locked | mode: exploratory | expected: manual: failure surfaces clearly; no skipped --no-gpg-sign sneak-in (per repo convention)
- [P1] stop-hook diff guard handles a file rename inside the test root | mode: test-framework | expected: bats test asserts a renamed test file (git status shows R) is allowed
- [P1] stop-hook diff guard handles a file rename WHERE THE OLD PATH was inside the test root and the NEW PATH is outside | mode: test-framework | expected: bats test asserts this is BLOCKED - moving a test file out of the test root is a production-code edit
- [P2] qa-reconcile-delta.sh runs against a doc using LaTeX-style references (\ref{FR-3}) instead of bare FR-3 | mode: test-framework | expected: bats test asserts behavior is pinned - either matched or not; document the choice
- [P2] render-qa-results.sh handles a verdict value containing case variation (e.g., "issues-found") | mode: test-framework | expected: bats test asserts case-insensitive match OR explicit normalization; no silent acceptance of malformed casing

## Non-applicable dimensions

- (none — all five dimensions yielded scenarios for this consolidation)
