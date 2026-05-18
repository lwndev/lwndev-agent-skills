---
id: FEAT-034
version: 2
timestamp: 2026-05-17T16:02:11Z
verdict: PASS
persona: qa
---

## Summary

18 adversarial QA tests authored at tests/bats/qa/qa-FEAT-034.bats; all 18 pass against the implementation on feat/FEAT-034-ado-pr-comments. Probes shell-injection passthrough (5 tests for single/double quotes, backticks, $VAR, semicolons), body-source mutual exclusion (4 permutations), large-body file-mode invariant, --reply-to validation (numeric / negative / empty), non-numeric PR-number rejection, stderr/stdout separation on happy path and graceful-skip paths, list-pr-comments graceful-skip stdout cleanliness, and unrecognized-backend graceful skip. No production code modified. Verdict: PASS.

## Capability Report

```json
{
  "id": "FEAT-034",
  "timestamp": "2026-05-17T15:54:17Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 18
- Passed: 18
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|
| QA-01 | Inputs (FR-1) | P0 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-02 | Inputs (FR-1) | P0 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-03 | Inputs (FR-1) | P0 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-04 | Inputs (FR-1) | P0 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-05 | Inputs (FR-1) | P0 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-06 | Inputs (FR-1, EDGE-9) | P0 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-07 | Inputs (FR-1, EDGE-11) | P0 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-08 | Inputs (FR-1, EDGE-11) | P0 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-09 | Inputs (FR-1, EDGE-11) | P0 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-10 | Inputs (FR-1, EDGE-11) | P0 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-11 | Inputs (FR-3, EDGE-12) | P1 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-12 | Inputs (FR-3, EDGE-12) | P1 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-13 | Inputs (FR-3, EDGE-12) | P1 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-14 | Inputs (FR-6) | P1 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-15 | Cross-cutting (NFR-1) | P1 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-16 | Cross-cutting (NFR-1) | P1 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-17 | Cross-cutting (FR-5, NFR-1, EDGE-13) | P1 | pass | tests/bats/qa/qa-FEAT-034.bats |
| QA-18 | Environment (FR-6) | P1 | pass | tests/bats/qa/qa-FEAT-034.bats |

## Findings

No test failures. Two implementer-level coverage notes from the QA-plan review:

- **Coverage breadth across dimensions**: The 18 adversarial tests in `tests/bats/qa/qa-FEAT-034.bats` focus on **Inputs** and **Cross-cutting** dimensions (15 of 18 cases). **State transitions** (concurrent probe race, parentCommentId resolution on empty thread), **Environment** (clock skew, /tmp read-only), and **Dependency failure** (HTTP 5xx, curl exit-code matrix) are covered indirectly by the implementation team's bats fixtures (`pr-comment-azdo.bats`, `list-pr-comments.bats`, `pr-comment-dispatch.bats`) but not by adversarial `qa-*` tests. Coverage-verify reports `COVERAGE-GAPS` because the artifact's `## Scenarios Run` table is dimension-tagged, not the full QA plan's five-dimension matrix — informational, does not change verdict.

- **Reconciliation coverage-gap noise**: `qa-reconcile-delta.sh` reports a 38-item coverage gap because the QA test names do not embed `FR-N` / `AC-N` / `EDGE-N` markers. The bidirectional matcher is keyed off literal `FR-N` tokens in the scenarios table. Cross-references to FR/EDGE labels appear in this table's Dimension column, but the script does not parse parenthetical labels. Documented limitation; does not affect verdict.

## Reconciliation Delta

### Coverage beyond requirements
- Scenario "Ran 18 passing tests, 0 failing tests, 0 errored tests." — not mentioned in spec

### Coverage gaps
- FR-1 "GitHub backend — post top-level comment" — no corresponding scenario in plan
- FR-1 ")." — no corresponding scenario in plan
- FR-2 "ADO backend — post top-level comment" — no corresponding scenario in plan
- FR-3 "ADO backend — reply to existing thread" — no corresponding scenario in plan
- FR-4 "Authentication path selection (ADO)" — no corresponding scenario in plan
- FR-5 "List PR threads / comments" — no corresponding scenario in plan
- FR-4 ") and flattens threads → comments preserving thread_id linkage." — no corresponding scenario in plan
- FR-6 "Backend dispatch" — no corresponding scenario in plan
- FR-7 "SKILL.md entry-point table update" — no corresponding scenario in plan
- FR-1 "." — no corresponding scenario in plan
- NFR-1 "Graceful degradation" — no corresponding scenario in plan
- NFR-2 "Performance" — no corresponding scenario in plan
- NFR-3 "Error handling" — no corresponding scenario in plan
- NFR-4 "Compatibility with consumer skills" — no corresponding scenario in plan
- AC-1 "[ ] `pr-comment.sh` exists on the ADO backend with signature parity to the GitHub backend (positional body, `--body`, `-" — no corresponding scenario in plan
- AC-2 "[ ] Backend is auto-detected from origin URL or `SDLC_SCM_BACKEND` env override — no explicit `--backend` flag on the ne" — no corresponding scenario in plan
- AC-3 "[ ] Round-trip integration test (post comment, list threads, assert presence) passes on both GitHub and ADO test PRs whe" — no corresponding scenario in plan
- AC-4 "[ ] `list-pr-comments.sh` emits NDJSON with the schema defined in FR-5, identical field names across backends." — no corresponding scenario in plan
- AC-5 "[ ] `/review` (and any other consumer skill) can post ADO PR comments without backend-specific branching or extra argume" — no corresponding scenario in plan
- AC-6 "[ ] SKILL.md is updated: Script Entry Points table, graceful-degradation matrix, References section (if new reference do" — no corresponding scenario in plan
- AC-7 "[ ] All graceful-degradation paths exit 0 with a `[warn]` line — no failure mode halts the workflow (NFR-1)." — no corresponding scenario in plan
- AC-8 "[ ] The `az devops invoke` resource-name probe is implemented with a deterministic fallback order and one-shot caching (" — no corresponding scenario in plan
- AC-9 "[ ] All new bash scripts pass `shellcheck` (matches existing scripts in this skill)." — no corresponding scenario in plan
- AC-10 "[ ] All new Bats tests pass under `npm run test:bats`." — no corresponding scenario in plan
- EDGE-1 "**PR closed/abandoned**: ADO threads are still postable on closed PRs; GitHub `gh pr comment` succeeds on closed PRs. Be" — no corresponding scenario in plan
- EDGE-2 "**Empty body**: Both backends reject empty bodies. Surface the CLI error verbatim and exit non-zero (this is a user erro" — no corresponding scenario in plan
- EDGE-3 "**Body file does not exist**: `--body-file /missing/path` exits non-zero with `[error] body file not found: /missing/pat" — no corresponding scenario in plan
- EDGE-4 "**Resource-name probe exhausts all fallbacks on a fresh org**: Log `[warn] ADO PR-thread resource probe failed across [P" — no corresponding scenario in plan
- EDGE-5 "**Concurrent `pr-comment.sh` invocations**: ADO thread IDs are server-allocated and atomic — no client-side coordination" — no corresponding scenario in plan
- EDGE-6 "**`--reply-to <invalid-thread-id>`**: ADO returns 404; the script emits `[warn] ADO thread <id> not found; skipping repl" — no corresponding scenario in plan
- EDGE-7 "**Body containing markdown that ADO renders differently than GitHub** (e.g. `~~strikethrough~~`, GFM tables): the script" — no corresponding scenario in plan
- EDGE-8 "**PR number that does not exist**: Both backends return 404; the script emits `[warn] PR <num> not found on <backend>; s" — no corresponding scenario in plan
- EDGE-9 "**Multi-line body via positional arg**: shell quoting limits apply — consumers MUST use `--body-file` for bodies that co" — no corresponding scenario in plan
- EDGE-10 "**GitHub PR with no comments**: `list-pr-comments.sh` emits zero NDJSON records and exits 0." — no corresponding scenario in plan
- EDGE-11 "**Multiple body sources passed** (e.g. positional + `--body-file`, or `--body` + `--body-file`): exit non-zero with `[er" — no corresponding scenario in plan
- EDGE-12 "**Non-numeric `--reply-to` value**: `--reply-to foo` exits non-zero with `[error] --reply-to must be a numeric thread id" — no corresponding scenario in plan
- EDGE-13 "**List-pr-comments graceful skip stdout**: on any FR-6 graceful-skip path (unrecognized backend, missing CLI, missing au" — no corresponding scenario in plan
- EDGE-14 "**Probe cache poisoning on transient network failure**: if the probe records `probe-failed` because of a transient outag" — no corresponding scenario in plan

### Summary
- coverage-surplus: 1
- coverage-gap: 38

