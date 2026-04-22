---
id: FEAT-022
version: 2
timestamp: 2026-04-22T02:38:00Z
verdict: PASS
persona: qa
---

## Summary

16 adversarial test-framework scenarios executed against the real FEAT-022 scripts (`branch-id-parse.sh` release extension, `check-idempotent.sh`, `completion-upsert.sh`, `reconcile-affected-files.sh`, `finalize.sh`). All 16 passed. Separately, the full shell-script bats regression suite (87 cases across `branch-id-parse.bats` + 6 finalizing-workflow fixtures) passed with zero regressions. Verdict: **PASS**.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

No drift from the plan's embedded capability report — both fresh and plan-time discovery agree.

## Execution Results

**Test file:** `scripts/__tests__/qa-FEAT-022.spec.ts` (committed as `f8de90e`).

**Runner invocation:** `npx vitest run scripts/__tests__/qa-FEAT-022.spec.ts`

```
 RUN  v3.2.4 /Users/leif/Projects/ai-skills/lwndev-marketplace

 ✓ scripts/__tests__/qa-FEAT-022.spec.ts (16 tests) 1164ms
   ✓ State transitions — idempotency > [P0] reconcile-affected-files: idempotent annotation (no double "planned" suffix)  678ms

 Test Files  1 passed (1)
      Tests  16 passed (16)
   Start at  19:34:30
   Duration  1.30s (transform 18ms, setup 0ms, collect 15ms, tests 1.16s, environment 0ms, prepare 34ms)
```

Total: 16. Passed: 16. Failed: 0. Errored: 0.

**Regression suite:** `bats plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/*.bats plugins/lwndev-sdlc/scripts/tests/branch-id-parse.bats` → 87 of 87 pass. This is the authoring test suite shipped across Phases 1–6 of the feature itself; re-running it confirms the QA vitest spec did not regress any of the authored assertions.

## Scenarios Run

### Inputs
- [P0] Shell-metachar branch-name treated as literal, no subshell (`feat/FEAT-001-$(touch SENTINEL)-x`) — PASS
- [P0] Unicode-lookalike release regex rejected (Cyrillic `в` in `release/plugin-в1.0.0`) — PASS (exit 1, no release match)
- [P1] 1000-character branch name does not overflow or crash — PASS
- [P1] `check-idempotent.sh` non-numeric prNumber `NaN` → exit 2 — PASS
- [P1] `check-idempotent.sh` prNumber `#142` (leading hash) → exit 2 — PASS
- [P2] PR-number prefix boundary: doc has `[#14]`, script called with `142` → exit 1, label `pr-line-mismatch` (boundary correctly anchored) — PASS
- [P2] PR-number match via `/pull/N` URL path → exit 0 — PASS
- [P1] `completion-upsert.sh` prUrl containing backticks is written literally, no command execution (sentinel file absent after run) — PASS
- [P1] Non-ASCII content in existing doc preserved byte-for-byte on upsert (αβγ, 🔧, عربى, κάτι all intact) — PASS

### State transitions
- [P0] Successive `completion-upsert.sh` runs yield `appended` then `upserted`; exactly one `## Completion` heading after (no duplication) — PASS
- [P0] `reconcile-affected-files.sh` idempotent annotation: already-annotated line not re-annotated (no `(planned but not modified) (planned but not modified)` double-suffix) — PASS

### Environment
- [P1] `LANG=C LC_ALL=C` does not garble existing non-ASCII doc content on upsert — PASS
- [P1] CRLF line endings preserved end-to-end across `completion-upsert.sh` (`keep\r\n` line retained) — PASS

### Dependency failure
- [P2] `gh` returning non-zero from `reconcile-affected-files.sh` exits 1 with `[warn] reconcile-affected-files` stderr prefix, no stdout — PASS

### Cross-cutting
- [P0] `finalize.sh` missing branch arg → exit 2, stderr contains `usage` — PASS
- [P0] `finalize.sh` empty branch arg → exit 2 — PASS

## Findings

No defects surfaced. The scripts correctly handle every adversarial input probed in this run. Key behaviours verified at the trust boundary:

- **No shell evaluation of inputs.** Neither branch names containing `$(...)` nor prUrls containing backticks trigger subshell execution. The sentinel-file assertion proves this empirically — the sentinels were not created.
- **Regex is ASCII-only as required.** The release-branch regex rejects homoglyph-attack-style unicode in the version marker, preserving the contract that only `release/<plugin>-vX.Y.Z` with ASCII `v` and ASCII digits classifies as a release branch.
- **PR-number matching is boundary-anchored.** A doc with `[#14]` does NOT spuriously match prNumber 142; the `pr-line-mismatch` label is correctly emitted. This was flagged in the Phase 2 implementation notes as a specific risk ("non-digit-or-EOL boundary so `14` does NOT match `142`") and the vitest run confirms the anchor holds.
- **Byte-level non-ASCII preservation.** Arabic, Greek, and emoji bytes in doc bodies round-trip through the mutating subscripts unchanged, both under UTF-8 and `LANG=C` locales. Line-ending preservation (CRLF kept on already-CRLF lines) works as specified.
- **Idempotency at subscript granularity.** Successive `completion-upsert.sh` and `reconcile-affected-files.sh` invocations produce no drift, no heading duplication, no repeated annotations. This matches FR-4's invariant that the top-level `finalize.sh` can be re-run after partial failure without corruption.
- **Graceful degradation on external failure.** A failing `gh` from `reconcile-affected-files.sh` produces a `[warn]`-prefixed stderr and exit 1 (documented non-fatal path); the script does not crash and does not mutate the doc.

## Reconciliation Delta

Computed against `requirements/features/FEAT-022-finalize-sh-subscripts-full.md`.

### Coverage surplus

Scenarios exercised in this QA run that do not map directly to a single FR / NFR / AC in the spec but add defensive coverage:

- **Unicode-lookalike release regex rejection** — FR-3 specifies an ASCII-only regex `^release/[a-z0-9-]+-v[0-9]+\.[0-9]+\.[0-9]+$` but does not explicitly call out homoglyph-attack rejection. The test is defensive and aligns with the regex's literal character-class constraint.
- **1000-character branch name stability** — NFR-1 targets wall-clock; no explicit input-length bound in the spec. Surplus probes a realistic boundary.
- **`completion-upsert.sh` non-ASCII preservation at `LANG=C`** — NFR-4 covers line-ending/fence awareness; byte-level non-ASCII preservation is stricter than the spec requires but matches the implicit expectation that requirement docs can contain any UTF-8 content.
- **`completion-upsert.sh` backtick-in-prUrl literal write** — Edge case coverage aligned with NFR-2 error handling; explicitly probes shell-injection surface.

### Coverage gap

FRs / NFRs / ACs / edge cases in the spec with no corresponding vitest scenario in this run. (Many of these ARE covered by the bats suite shipped with the feature — the gap here is specifically vs this QA run, not vs total feature coverage.)

- **FR-8 BK-5 commit+push failure path** — not vitest-exercised here; bats `finalize.bats` covers it at the composition level with stubs.
- **FR-9 merge failure after successful BK-5 push (no-rollback invariant)** — not vitest-exercised; bats `finalize.bats` has the explicit no-rollback assertion (zero `git revert`/`git reset --hard` in tracer) covered at the composition level.
- **NFR-1 wall-clock < 5s end-to-end** — measured in Phase 6 bats (`finalize.e2e.bats`) at ~600ms; not re-measured in this QA run.
- **NFR-5 token-usage acceptance criterion** — PR-description deliverable, not testable as an automated scenario in either framework.
- **Edge case 8 (git push rejected as non-fast-forward)** — not vitest-exercised; bats `finalize.bats` covers BK-5 push failure in stub form.
- **Edge case 9 (`gh pr merge` fails after successful BK-5 push)** — covered in `finalize.bats` by the no-rollback assertion.
- **Edge case 11 (idempotent second run after full success — branch already deleted)** — neither vitest nor bats explicitly covers this. The Phase 6 e2e covers the "first run failed between BK-5 and merge" idempotency path but not the "first run succeeded entirely; rerun sees deleted branch" path. Candidate for future exploratory verification.
- **Concurrency: two `finalize.sh` invocations on the same branch racing for `.git/index.lock`** — not exercised in any framework; exploratory-only.
- **SIGINT delivered mid-BK-5 between `git add` and `git commit`** — not exercised; exploratory-only.
- **Manual verification deliverables (disposable `release/<plugin>-v9.99.0` branch; full orchestrator chain E2E)** — explicitly exploratory, recorded in plan Phase 6.

### Summary

coverage-surplus: 4
coverage-gap: 9 (of which 4 are exploratory-only by design and 4 are covered by the shipped bats suite at the composition level)
