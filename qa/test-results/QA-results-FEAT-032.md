---
id: FEAT-032
version: 2
timestamp: 2026-05-10T02:36:38Z
verdict: PASS
persona: qa
---

## Summary

- Verdict: **PASS**. 7/7 adversarial QA tests passed.
- Coverage focus: argument hardening for `adopt-qa-test.sh` (shell-special characters, traversal, i18n) and FR-9 safety-net glob anchoring probes (extension, subdirectory, bats path).
- Adversarial findings: zero defects; three coverage-probe documentations of v1 glob anchoring (intentional per CLAUDE.md / Edge Case 17 lockstep).
- Run: `npx vitest run tests/unit/qa-feat-032-adversarial.test.ts` — 7 tests, 7 passed, 0 failed, 0 errored.

## Capability Report

```json
{
  "id": "FEAT-032",
  "timestamp": "2026-05-10T02:26:30Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 7
- Passed: 7
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

### Inputs
- [P0] Shell-special characters in QA-test path are passed safely (no command injection) | mode: test-framework | result: PASSED — sentinels untouched regardless of exit code
- [P1] Non-ASCII characters in QA-test body preserve content byte-for-byte through `git mv` adoption | mode: test-framework | result: PASSED — content bit-for-bit equal post-adoption
- [P2] Path-traversal argument resolves outside repo and is rejected | mode: test-framework | result: PASSED — non-zero exit, no write at traversal-implied target

### State transitions
- [P0] FR-9 safety-net glob anchoring: a tracked `qa-canonical.test.ts` IS caught by the v1 glob (control) | mode: test-framework | result: PASSED
- [P1] FR-9 coverage probe: tracked `qa-*.test.tsx` under `tests/unit/` is NOT caught by v1 glob | mode: test-framework | result: DOCUMENTED v1 surface area
- [P1] FR-9 coverage probe: tracked `qa-*.test.ts` in a `tests/unit/sub/` subdirectory is NOT caught | mode: test-framework | result: DOCUMENTED v1 surface area
- [P1] FR-9 coverage probe: tracked `qa-*.bats` directly under `tests/bats/` (not in `tests/bats/qa/`) is NOT caught | mode: test-framework | result: DOCUMENTED v1 surface area

### Environment
- Justification: not applicable. The addressing-qa-findings v1 surface is bash + node + git only. None of the environment-failure scenarios in the plan (offline, low disk, slow network, locale/timezone, RO filesystem) admit a deterministic test-framework reproduction without external infrastructure that would itself wedge CI.

### Dependency failure
- Justification: not applicable in test-framework mode. The plan's P0 dependency-failure (`npm test` hangs indefinitely) is fundamentally exploratory — reproducing a hang inside a `vitest run` would wedge the very runner asserting it. The remaining items (rate-limit, case-collision rename, scoped re-validation) are exploratory or are already covered by existing bats fixtures (see `## Reconciliation Delta`).

### Cross-cutting
- [P1] i18n: non-ASCII identifier preservation through `git mv` adoption | mode: test-framework | result: PASSED — exercised inline as part of Inputs P1 above (cross-listed for dimension coverage).

## Findings

- **FR-9 safety-net glob coverage probe (State transitions / coverage report)** — the v1 glob set in `preflight-checks.sh` (`tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, `tests/bats/qa/qa-*.bats`) is anchored to canonical ephemeral paths and does NOT match: (a) `qa-*.test.tsx` extension under `tests/unit/`; (b) `qa-*` files in subdirectories such as `tests/unit/sub/qa-foo.test.ts`; (c) `qa-*.bats` files placed directly under `tests/bats/` (i.e., not in `tests/bats/qa/`). This is the documented v1 surface area per CLAUDE.md (anchoring keeps permanent QA-loop infrastructure under `tests/bats/skills/<skill>/` clear of the gate). Surfaced as a coverage-report finding rather than a defect; future expansion of the glob set must land in lockstep with FR-5 dispatch support (Edge Case 17).
- **adopt-qa-test.sh argument hardening (Inputs P0/P1/P2)** — confirmed via 3 adversarial probes that (a) shell-special characters in QA-test path do NOT trigger command injection (sentinel files untouched regardless of exit code); (b) traversal arguments outside the repo are rejected with non-zero exit and no write occurs at the traversal-implied target; (c) non-ASCII content in the QA test body survives `git mv` byte-for-byte during adoption.
- No production-code defects found; FR-2 / `## Report-Only Mode` honored (no edits outside `tests/unit/`, `qa/test-results/`, `qa/test-plans/`).

## Reconciliation Delta

### Coverage beyond requirements
- Scenario "Ran 7 passing tests, 0 failing tests, 0 errored tests." — not mentioned in spec

### Coverage gaps
- FR-1 "QA tests are ephemeral on the feature branch" — no corresponding scenario in plan
- FR-2 "QA test source embedded in the artifact" — no corresponding scenario in plan
- FR-3 "executing-qa re-QA mode" — no corresponding scenario in plan
- FR-9 "." — no corresponding scenario in plan
- FR-12 ")" — no corresponding scenario in plan
- FR-13 ") only consults those three rows after a re-QA invocation." — no corresponding scenario in plan
- FR-4 "New skill addressing-qa-findings" — no corresponding scenario in plan
- FR-7 "dispatch contract) to decide. No new state field is required; in particular, no lastStepKind is introduced." — no corresponding scenario in plan
- FR-4 "EC) — see Edge Case 13." — no corresponding scenario in plan
- FR-5 ") on that file" — no corresponding scenario in plan
- FR-5 "partial-success path, see Edge Case 14). The previously-emitted stdout path lines remain valid; they are the source of truth for adoptedTests on partial-success" — no corresponding scenario in plan
- FR-5 "Deterministic adoption script" — no corresponding scenario in plan
- FR-6 "Adopted-test naming convention" — no corresponding scenario in plan
- FR-7 "Orchestrator verdict-based branching" — no corresponding scenario in plan
- FR-4 "); on its return, advance to finalizing-workflow |" — no corresponding scenario in plan
- FR-3 ") |" — no corresponding scenario in plan
- FR-3 "establishes that re-QA mode cannot return EXPLORATORY-ONLY; therefore the EXPLORATORY-ONLY → finalizing-workflow row in the table above is consulted only when q" — no corresponding scenario in plan
- FR-7 "a: pauseReason enum extension" — no corresponding scenario in plan
- FR-7 "/ Edge Case 14) — extend the closed enum currently validated by plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh in cmd_pause (aroun" — no corresponding scenario in plan
- FR-8 "Re-QA loop cap N=2" — no corresponding scenario in plan
- FR-1 "cost analysis ("2× fix attempts + 2× re-QA executions")." — no corresponding scenario in plan
- FR-9 "finalizing-workflow safety-net check" — no corresponding scenario in plan
- FR-5 "; until then, scanning for them is a no-op (no false positives)." — no corresponding scenario in plan
- FR-9 "'s write convention — the safety net catches any qa--prefixed leakage anywhere under the tracked tree, not just the dimension-named files the canonical writer p" — no corresponding scenario in plan
- FR-10 "Set-based parity assertion" — no corresponding scenario in plan
- FR-11 "Length-assertion audit" — no corresponding scenario in plan
- FR-12 "QA artifact versioning across re-QA" — no corresponding scenario in plan
- FR-3 "), it overwrites qa/test-results/QA-results-{ID}.md with the latest results. Prior results are NOT preserved as separate files; the artifact represents the curr" — no corresponding scenario in plan
- FR-9 "acceptance criterion (re-QA artifact-overwrite Bats fixture)." — no corresponding scenario in plan
- FR-4 "fix-phase precheck without requiring the precheck to whitelist the artifact path. On re-QA mode, the artifact commit replaces (overwrites + commits) the prior a" — no corresponding scenario in plan
- FR-13 "Adoption ownership" — no corresponding scenario in plan
- FR-14 "CLAUDE.md documentation" — no corresponding scenario in plan
- NFR-1 "Performance" — no corresponding scenario in plan
- NFR-2 "Error handling" — no corresponding scenario in plan
- NFR-3 "Backwards compatibility" — no corresponding scenario in plan
- NFR-4 "Test coverage" — no corresponding scenario in plan
- AC-1 "[ ] `executing-qa` no longer leaks `qa-<dimension>` prefixed files past merge (verified by `finalizing-workflow` safety-" — no corresponding scenario in plan
- AC-2 "[ ] New `addressing-qa-findings` skill exists at `plugins/lwndev-sdlc/skills/addressing-qa-findings/SKILL.md` with devel" — no corresponding scenario in plan
- AC-3 "[ ] `addressing-qa-findings` consumes `qa/test-results/QA-results-{ID}.md`, reproduces failures, writes production fixes" — no corresponding scenario in plan
- AC-4 "[ ] `addressing-qa-findings` operates in two distinct phases (fix, adopt) with auto-detected dispatch from the `{qaLastV" — no corresponding scenario in plan
- AC-5 "[ ] `adopt-qa-test.sh` deterministically renames QA tests to `{module}.qa.{ext}` siblings; supports Vitest and Bats; exi" — no corresponding scenario in plan
- AC-6 "[ ] Orchestrator branches to `addressing-qa-findings` (fix phase) on `ISSUES-FOUND` verdict; loops with cap N=2; pauses " — no corresponding scenario in plan
- AC-7 "[ ] `EXPLORATORY-ONLY` and initial-run `PASS` verdicts advance directly to `finalizing-workflow` (no fix loop)" — no corresponding scenario in plan
- AC-8 "[ ] `PASS` verdict in re-QA mode (after fix phase) triggers `addressing-qa-findings` adopt phase, then advance" — no corresponding scenario in plan
- AC-9 "[ ] `ERROR` verdict pauses with `qa-error` (no fix loop)" — no corresponding scenario in plan
- AC-10 "[ ] `finalizing-workflow` safety-net blocks merge if any `qa-*` file remains; allows `*.qa.*` siblings" — no corresponding scenario in plan
- AC-11 "[ ] `tests/unit/shared-scripts.test.ts:102-117` parity assertion is set-based; tolerates `*.qa.bats` siblings; hard-code" — no corresponding scenario in plan
- AC-12 "[ ] All length-based assertions over QA-relevant directories are audited and either relaxed or documented as intentional" — no corresponding scenario in plan
- AC-13 "[ ] `CLAUDE.md` documents the new QA lifecycle and `*.qa.*` adoption convention" — no corresponding scenario in plan
- AC-14 "[ ] Workflow state schema includes `qaFixAttempts`, `qaLastVerdict`, `adoptedTests`" — no corresponding scenario in plan
- AC-15 "[ ] QA artifact embeds test source under each finding's `## Reproduction` section" — no corresponding scenario in plan
- AC-16 "[ ] FR-12: `executing-qa` re-QA mode overwrites `qa/test-results/QA-results-{ID}.md` (does not version per-attempt); Bat" — no corresponding scenario in plan
- AC-17 "[ ] FR-13: no skill or script other than `addressing-qa-findings` deletes any `qa-*` file (assertion via grep over plugi" — no corresponding scenario in plan
- AC-18 "[ ] Re-QA loop attempt = full pass over all findings + 1 re-QA execution (per FR-8); per-finding loops do NOT consume se" — no corresponding scenario in plan
- AC-19 "[ ] `--qa-loop-cap <N>` flag accepted on resume from `qa-loop-exhausted`; resets counter and continues" — no corresponding scenario in plan
- AC-20 "[ ] Full test suite green; new behaviors covered by Vitest or Bats at the canonical leaf" — no corresponding scenario in plan
- AC-21 "[ ] End-to-end Bats fixture exercises `ISSUES-FOUND → addressing-qa-findings (fix) → re-QA → addressing-qa-findings (ado" — no corresponding scenario in plan
- AC-22 "[ ] FR-2: `render-qa-results.sh` emits language-aware fences (e.g. ` ```typescript `, ` ```bash `) and a path-comment he" — no corresponding scenario in plan
- AC-23 "[ ] FR-3: re-QA mode is entered iff the `qa-baseline` marker file `.sdlc/qa/.executing-qa-baseline-{ID}` is present AND " — no corresponding scenario in plan
- AC-24 "[ ] FR-4: fix-phase pre-check fails fast on a dirty working tree with the literal message `failed | working tree dirty; " — no corresponding scenario in plan
- AC-25 "[ ] FR-5: on the first `adopt-qa-test.sh` exit-2 across N candidate files, the M previously-moved files remain at their " — no corresponding scenario in plan
- AC-26 "[ ] FR-12: `executing-qa` commits `qa/test-results/QA-results-{ID}.md` before returning, with message `qa({ID}): record " — no corresponding scenario in plan
- AC-27 "[ ] FR-7a: `workflow-state.sh` `cmd_pause` accepts the four new pause reasons (`qa-error`, `qa-loop-exhausted`, `fix-sui" — no corresponding scenario in plan
- AC-28 "[ ] FR-8: `--approve-advance` and `--qa-loop-cap <N>` flags accepted by `orchestrating-workflows` resume; unknown flags " — no corresponding scenario in plan
- EDGE-1 "**Adoption: no peer test exists for the SUT** — adoption script exits 2; orchestrator pauses with `adoption-failed`. Use" — no corresponding scenario in plan
- EDGE-2 "**Adoption: multiple plausible peer tests** — adoption script exits 2 (ambiguity). User picks one and either adjusts imp" — no corresponding scenario in plan
- EDGE-3 "**Adoption: QA test imports a helper that lives next to the QA test (e.g. `./helpers/qa-mock.ts`)** — after `git mv`, th" — no corresponding scenario in plan
- EDGE-4 "**Re-QA mode invoked without prior QA test files** — `executing-qa` emits `ERROR` with summary indicating the missing pr" — no corresponding scenario in plan
- EDGE-5 "**Loop cap exhaustion (`qaFixAttempts == 2` AND verdict still `ISSUES-FOUND`)** — orchestrator pauses with `qa-loop-exha" — no corresponding scenario in plan
- EDGE-6 "**`EXPLORATORY-ONLY` verdict** — no findings, no test files to adopt; orchestrator advances to finalize directly. `execu" — no corresponding scenario in plan
- EDGE-7 "**`ERROR` verdict on first `executing-qa` run** — orchestrator pauses with `qa-error`; `addressing-qa-findings` is NOT i" — no corresponding scenario in plan
- EDGE-8 "**User manually deletes QA test files mid-workflow** — re-QA mode emits `ERROR`; orchestrator pauses. No silent recovery" — no corresponding scenario in plan
- EDGE-9 "**`finalizing-workflow` safety-net trips on a `*.qa.*` file** — does NOT trip; the glob is `qa-*` prefix only. Adopted s" — no corresponding scenario in plan
- EDGE-10 "**`finalizing-workflow` safety-net trips on a manually-named `qa-foo.test.ts` outside the workflow** — trips; user must " — no corresponding scenario in plan
- EDGE-11 "**Squash vs merge-commit policy** — squash-merge hides `qa(test):` and `qa(adopt):` commits from main history; merge-com" — no corresponding scenario in plan
- EDGE-12 "**`addressing-qa-findings` invoked without a `qa/test-results/QA-results-{ID}.md`** — skill exits with `failed | no QA a" — no corresponding scenario in plan
- EDGE-13 "**Full-suite build-health gate fails after fix in FR-4 step 4** — `addressing-qa-findings` exits with `failed | full sui" — no corresponding scenario in plan
- EDGE-14 "**Partial-success adoption (FR-5 aggregation)** — On the first `adopt-qa-test.sh` exit-2 across multiple QA test files, " — no corresponding scenario in plan
- EDGE-15 "**User resumes from `qa-loop-exhausted` pause with `--qa-loop-cap <N>`** — counter is reset to 0; the workflow continues" — no corresponding scenario in plan
- EDGE-16 "**User resumes from `qa-loop-exhausted` pause with "approve advance"** — counter is preserved (informational); orchestra" — no corresponding scenario in plan
- EDGE-17 "**v1 user on Python or Go project** — pytest and go-test are out of FR-5 v1 dispatch; the FR-9 safety net's `qa-*.py` / " — no corresponding scenario in plan

### Summary
- coverage-surplus: 1
- coverage-gap: 81

