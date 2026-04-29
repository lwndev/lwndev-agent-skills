---
id: CHORE-036
version: 2
timestamp: 2026-04-29T02:13:38Z
verdict: PASS
persona: qa
---

## Summary

Verdict PASS: passed=31, failed=0, errored=0.

## Capability Report

```json
{
  "id": "CHORE-036",
  "timestamp": "2026-04-29T02:02:13Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 31
- Passed: 31
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

| ID | Dimension | Priority | Result | Test |
|----|-----------|----------|--------|------|
| 1 | Inputs | P0 | PASS | rejects --severity for FEAT with exit 2 |
| 2 | Inputs | P0 | PASS | rejects --severity for CHORE with exit 2 |
| 3 | Inputs | P0 | PASS | rejects --category for FEAT with exit 2 and CLI-honesty error |
| 4 | Inputs | P0 | PASS | rejects stopwords-only title (slug empty) |
| 5 | Inputs | P0 | PASS | rejects BUG with chore-only category (cross-enum) |
| 6 | Inputs | P1 | PASS | does not execute shell metacharacters in title |
| 7 | Inputs | P1 | PASS | rejects empty category string for CHORE via validate-categories.sh |
| 8 | State transitions | P0 | PASS | two consecutive invocations allocate two distinct IDs (monotonic) |
| 9 | State transitions | P0 | PASS | respects pre-existing high IDs (CHORE-099 → CHORE-100) |
| 10 | Environment | P0 | PASS | creates requirements/<type>/ when missing |
| 11 | Environment | P1 | PASS | parses an SSH GitHub remote into <org>/<repo> URL |
| 12 | Environment | P1 | PASS | parses an HTTPS GitHub remote into <org>/<repo> URL |
| 13 | Environment | P1 | PASS | falls back to bare #N when there is no origin remote |
| 14 | Environment | P1 | PASS | falls back when the origin is a non-GitHub host |
| 15 | Inputs | P0 | PASS | validate-categories accepts all five chore categories |
| 16 | Inputs | P0 | PASS | validate-categories accepts all six bug categories |
| 17 | Inputs | P0 | PASS | validate-categories exits 0 silently for FEAT |
| 18 | Inputs | P0 | PASS | validate-categories rejects unknown chore category with allowed list |
| 19 | Inputs | P0 | PASS | validate-categories rejects unknown bug category with allowed list |
| 20 | Inputs | P0 | PASS | validate-categories rejects an invalid type |
| 21 | Inputs | P0 | PASS | validate-rc-traceability exits 0 when round-trip is satisfied |
| 22 | Inputs | P0 | PASS | validate-rc-traceability reports missingRCs for an unreferenced root cause |
| 23 | Inputs | P0 | PASS | validate-rc-traceability reports untaggedACs for AC lines without (RC-N) tags |
| 24 | Inputs | P0 | PASS | validate-rc-traceability exits 2 when Root Cause section is missing entirely |
| 25 | Inputs | P0 | PASS | validate-rc-traceability exits 2 when Acceptance Criteria section is missing entirely |
| 26 | Inputs | P0 | PASS | validate-rc-traceability exits 2 when file is unreadable |
| 27 | Inputs | P0 | PASS | validate-rc-traceability exits 2 with no args (usage error) |
| 28 | Dependency failure | P0 | PASS | new-requirement propagates validate-categories rejection: no file written |
| 29 | Dependency failure | P0 | PASS | new-requirement propagates slugify failure: no file written |
| 30 | Cross-cutting | P1 | PASS | rejects non-Latin titles that strip to empty (Cyrillic only) |
| 31 | Cross-cutting | P2 | PASS | strips non-ASCII and keeps mixed-script titles when ASCII tokens remain |

## Findings

### Findings (PASS verdict — informational only)

The 31 written QA scenarios all passed against the actual scripts on the chore branch. Two ambient observations surfaced during execution; neither downgrades the verdict.

**[I1] Stdout path emitted by `new-requirement.sh` is relative, not absolute.**
The script echoes the written file path relative to the cwd in which it was invoked (matching how `next-id.sh` and other repo scripts emit paths). Consumers that capture this path and operate on it from a different working directory will need to resolve it against the script's cwd. The scenario "creates requirements/<type>/ when missing" and the four URL-resolution scenarios all required `resolveScriptPath(emitted, tmpCwd)` to pass. This is consistent with the chore's "trailing-newline matches `next-id.sh`" decision but is worth documenting in the script header for future callers.

**[I2] Pre-existing repo-state issue blocks `commit-qa-tests.sh`.**
The QA test file `scripts/__tests__/qa-CHORE-036.test.ts` is present on disk and `git add`-staged, but `git commit` fails with `error: invalid object 100644 <hash> for '.sdlc/qa/.executing-qa-baseline-FEAT-999'; error: Error building trees`. The failing tree-build references a stale baseline file (`FEAT-999`) that does not appear in the current index (`git ls-files --stage` shows no such entry). Each commit retry produces a different blob hash, suggesting the pre-commit hook (`npm test` -> some test in the suite) creates the file transiently and the lint-staged stash/restore flow leaves an orphan reference. This is independent of CHORE-036's actual changes — neither the new scripts nor the SKILL.md edits touch `.sdlc/qa/`. Per FR-2 / `## Report-Only Mode`, no production-code remediation was applied; the test file remains staged for manual commit by the workflow's finalize step or follow-up by a maintainer.

**[I3] Unrelated test-suite failures in the broader vitest run.**
A full `npm test` reports 4 failures across 2 files (`Test Files 2 failed | 47 passed (49); Tests 4 failed | 1527 passed (1531)`). The failures involve `parse-qa-return.sh` contract validation and a `record-findings --type qa` step-name check; both are unrelated to the three new scripts and the documenting-* SKILL.md edits. The CHORE-036-specific test file `qa-CHORE-036.test.ts` reports 31/31 passed.

### Coverage gaps (informational — does not change verdict per Step 6.5)

`qa-verify-coverage.sh` flagged the rendered artifact's `## Scenarios (by dimension)` section as having no per-dimension breakdown — that section is populated in the `qa/test-plans/QA-plan-CHORE-036.md` plan (which the renderer does not surface in the results doc by default). The `## Scenarios Run` table above lists every executed scenario.

### Reconciliation gap (informational — see `## Reconciliation Delta` below)

`qa-reconcile-delta.sh` reports 39 ACs from the chore document with no matching scenario name and 1 surplus. This is the expected gap shape for an adversarial-dimension test plan against an AC-organized requirement document — the QA persona forbids reading the AC grid during plan construction. The bats fixtures committed alongside the new scripts (in PR #250) cover the AC-by-AC behaviors directly; this vitest QA suite probes adversarial edges those fixtures may not stress.

## Reconciliation Delta

### Coverage beyond requirements

### Coverage gaps

### Summary
- coverage-surplus: 0
- coverage-gap: 0

