---
id: FEAT-025
version: 2
timestamp: 2026-04-23T00:27:05Z
verdict: PASS
persona: qa
---

## Summary

28 vitest adversarial scenarios exercised across all six managing-work-items scripts, run via subprocess to bridge the repo's TypeScript harness and the feature's shell-script implementation. Two P0 bugs surfaced during the write-and-run loop (invalid JSON for leading-zero refs in `backend-detect.sh`; pr-link.sh did not reject empty-string args) — both fixed in-loop and re-verified with all 28 vitest tests passing and the full 95-test bats suite still green. Full repo vitest (1328 tests) and `npm run validate` also pass on the fix commit.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

Notes: the capability report aligns with the plan's embedded report (no drift). The feature ships shell scripts, so the authoritative test harness is bats — skill-scoped suites under `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/` delivered ~95 assertions across phases 1–3. The vitest suite recorded here is supplementary: it exercises the P0 scenarios through a subprocess bridge to keep the feature inside the repo's existing CI surface.

## Execution Results

- Total: 28
- Passed: 28
- Failed: 0
- Errored: 0
- Exit code: 0
- Duration: 254ms (vitest reported wall-clock)
- Test files: [`scripts/__tests__/qa-managing-work-items.test.ts`]

Supplementary bats run:

- Total: 95
- Passed: 95
- Failed: 0
- Errored: 0
- Exit code: 0
- Test files: [`plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/backend-detect.bats`, `extract-issue-ref.bats`, `pr-link.bats`, `render-issue-comment.bats`, `post-issue-comment.bats`, `fetch-issue.bats`]

Repo-wide regression:

- Total: 1328
- Passed: 1328
- Failed: 0
- Errored: 0
- Exit code: 0
- Test files: full vitest suite

## Scenarios Run

| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|
| backend-detect-whitespace-only | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| backend-detect-empty | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| backend-detect-trim-whitespace | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| backend-detect-leading-zeros | Inputs | P0 | PASS (after fix) | qa-managing-work-items.test.ts |
| backend-detect-negative-number | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| backend-detect-alphanumeric-jira | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| backend-detect-lowercase-jira | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| backend-detect-underscore-separator | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| backend-detect-unicode-homoglyph | Inputs | P1 | PASS | qa-managing-work-items.test.ts |
| extract-issue-ref-missing-section | Inputs | P1 | PASS | qa-managing-work-items.test.ts |
| extract-issue-ref-multiple-matches | Inputs | P1 | PASS | qa-managing-work-items.test.ts |
| extract-issue-ref-file-missing | Inputs | P1 | PASS | qa-managing-work-items.test.ts |
| extract-issue-ref-missing-arg | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| pr-link-empty-arg | Inputs | P0 | PASS (after fix) | qa-managing-work-items.test.ts |
| pr-link-null-ref | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| pr-link-github-format | Inputs | P1 | PASS | qa-managing-work-items.test.ts |
| pr-link-jira-format | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| render-issue-comment-invalid-backend | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| render-issue-comment-invalid-type | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| render-issue-comment-malformed-json | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| post-issue-comment-null-ref-skip | Environment | P0 | PASS | qa-managing-work-items.test.ts |
| post-issue-comment-missing-args | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| fetch-issue-null-ref | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| fetch-issue-missing-arg | Inputs | P0 | PASS | qa-managing-work-items.test.ts |
| cross-script-pr-link-backend-detect-consistency | Cross-cutting | P0 | PASS | qa-managing-work-items.test.ts |
| determinism-backend-detect | State transitions | P0 | PASS | qa-managing-work-items.test.ts |
| determinism-pr-link | State transitions | P0 | PASS | qa-managing-work-items.test.ts |
| script-file-integrity | Cross-cutting | P1 | PASS | qa-managing-work-items.test.ts |

## Findings

Two P0 bugs were uncovered by the initial write-and-run loop. Both were fixed in the same executing-qa run (commit `348376b`) and the suite re-ran green.

### Finding 1 — backend-detect.sh emitted invalid JSON for leading-zero references

- **Severity**: P0
- **Dimension**: Inputs
- **Failing test**: `FEAT-025 QA: managing-work-items scripts — P0 adversarial scenarios > backend-detect.sh: inputs dimension > treats leading zeros as a numeric value (not a string)`
- **Reproduction**: `bash plugins/lwndev-sdlc/skills/managing-work-items/scripts/backend-detect.sh '#007'`
- **Pre-fix output**: `{"backend":"github","issueNumber":007}` (invalid — RFC 8259 disallows leading zeros on numeric literals)
- **Evidence**: `JSON.parse(stdout)` raised `SyntaxError: Unexpected number in JSON at position 35`
- **Root cause**: line 45 of `backend-detect.sh` passed the raw regex capture (`007`) to `printf '%s'` without stripping leading zeros. Any downstream `jq` or JSON-aware caller would reject the output.
- **Fix**: force base-10 interpretation with `$((10#${BASH_REMATCH[1]}))` so zeros are dropped before emission. Commit `348376b`.

### Finding 2 — pr-link.sh returned exit 0 for an empty-string argument

- **Severity**: P0
- **Dimension**: Inputs
- **Failing test**: `FEAT-025 QA: managing-work-items scripts — P0 adversarial scenarios > pr-link.sh: inputs dimension > exits 2 on empty arg`
- **Reproduction**: `bash plugins/lwndev-sdlc/skills/managing-work-items/scripts/pr-link.sh ''`
- **Pre-fix output**: exit 0, empty stdout (should have been exit 2, per the feature's FR-3 contract and matching backend-detect.sh's arg-shape semantics)
- **Evidence**: the `$#` arg-count check on line 24 passed (1 positional arg, which happened to be empty); delegation to backend-detect.sh exited 2, but `|| true` on line 37 swallowed the error and the default case fell through to exit 0.
- **Root cause**: inconsistent arg-shape contract between `pr-link.sh` and the upstream `backend-detect.sh`. The empty-string case leaked through.
- **Fix**: add an explicit post-trim emptiness check before the backend-detect delegation. Commit `348376b`.

### No residual failing tests

After the two fixes, all 28 vitest scenarios pass, all 95 bats tests pass, the repo's 1328-test vitest suite passes, and `npm run validate` reports no plugin validation errors.

## Reconciliation Delta

### Coverage beyond requirements

- `Cross-script integration: pr-link invokes backend-detect` — not explicitly called out in any FR of the requirements document, but implied by FR-3's "internally invoke `backend-detect.sh` (FR-1) to classify the reference" clause. The vitest scenario verifies the two scripts remain consistent across the full classification matrix (6 reference shapes). This is diligent adversarial testing rather than over-testing.
- `Unicode homoglyph rejection` (e.g., full-width `＃`) — no FR explicitly names Unicode homoglyphs. The scenario is implicit in FR-1's ASCII-only regex but worth calling out because the homoglyph surface is easy to miss in review.
- `Determinism / idempotency` (NFR-3 mapping) — NFR-3 in the requirements doc specifies "Idempotent rendering: same context-json → identical stdout" for rendering scripts only. The QA plan broadened the check to `backend-detect` and `pr-link` (both pure functions). Surplus coverage, no gap.

### Coverage gaps

- **NFR-4 (Token Savings Measurement)** — the requirements doc's NFR-4 requires a pre/post token-savings measurement within ±30% of the ~2,200–2,800 tok/workflow estimate. No QA scenario exercises this; it is a post-merge observational measurement, not a testable invariant. Recommendation: close this gap with a measurement note in the PR description or a follow-up observational PR rather than a test.
- **FR-4 ADF path — "context JSON contains ~500 items in a list" (P1 performance scenario)** — the plan listed this as a test-framework scenario, but no vitest assertion exercises it in this run. The bats fixture for `render-issue-comment.sh` covers a 3-item ADF list expansion (`ok 80`) but not the 500-item stress case. Documented gap; would require a bats extension or a dedicated vitest perf test.
- **Live integration against a throwaway GitHub issue (plan's Integration Tests section)** — the requirements doc's Testing Requirements section names a `RUN_LIVE_ISSUE_TESTS=1` environment-flag gated integration round-trip. This run did not execute any live API calls (scripts tested the no-reference skip paths only). Documented gap; intentional per the "hidden behind a flag" design.
- **Jira tier fallback scenarios exercised via end-to-end MCP/acli** — bats covers these via PATH-shadowed stubs; no live-tier fallback scenario was exercised here. Typical for this QA harness; the bats stubs are authoritative for the graceful-degradation string contracts.

### Summary

- coverage-surplus: 3
- coverage-gap: 4
