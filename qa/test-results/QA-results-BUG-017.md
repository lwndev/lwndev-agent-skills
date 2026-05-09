---
id: BUG-017
version: 2
timestamp: 2026-05-09T22:30:55Z
verdict: PASS
persona: qa
---

## Summary

Verdict PASS: passed=17, failed=0, errored=0.

## Capability Report

```json
{
  "id": "BUG-017",
  "timestamp": "2026-05-09T22:24:51Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 17
- Passed: 17
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

### Inputs
- [P0] derived count = N for N real-skill directories with no .-prefix or _-prefix entries | mode: test-framework | expected: PASSED
- [P0] excludes .-prefix entries (.cache, .git-keep) from the count | mode: test-framework | expected: PASSED
- [P0] excludes _-prefix entries (_archived, _draft) from the count -- the regression that motivated this bug | mode: test-framework | expected: PASSED
- [P0] excludes BOTH .-prefix and _-prefix entries simultaneously | mode: test-framework | expected: PASSED
- [P1] excludes regular files (.DS_Store, README.md) from the count | mode: test-framework | expected: PASSED
- [P1] excludes single-character . and _ directory names | mode: test-framework | expected: PASSED
- [P1] yields zero count for an empty skills directory | mode: test-framework | expected: PASSED
- [P2] handles Unicode-named skill directories without stripping non-ASCII | mode: test-framework | expected: PASSED
- [P2] handles directories starting with digits (01-first, 99-last) | mode: test-framework | expected: PASSED

### State transitions
- [P0] argument-hint.test.ts loads skillData inside beforeAll, not inside an it() (cascade-decoupling AC) | mode: test-framework | expected: PASSED
- [P0] build.test.ts derives the validate-count from disk filter (RC-2 line 90 + 42 fix) | mode: test-framework | expected: PASSED
- [P0] both files filter _-prefix entries (RC-2) | mode: test-framework | expected: PASSED
- [P0] test names at build.test.ts:39 and :71 no longer embed literal 13 (RC-2) | mode: test-framework | expected: PASSED

### Environment
- [P1] symlinked subdirectory classification documented (Dirent.isDirectory() returns false for symlinks; concrete-skill included, symlinked-skill excluded) | mode: test-framework | expected: PASSED

### Dependency failure
- [P1] derived count from disk equals on-disk skill count for the real plugin (snapshot: 13) | mode: test-framework | expected: PASSED
- [P1] npm run validate emits one Validating: line per real skill (no extra, no missing) | mode: test-framework | expected: PASSED

### Cross-cutting
- [P2] running argument-hint.test.ts and build.test.ts in the same suite is parallel-safe by construction (no writeFile/mkdir against SKILLS_DIR or PLUGIN_DIR) | mode: test-framework | expected: PASSED

## Findings

No defects detected. All 17 written QA tests passed; 1619/1619 across the full vitest suite passed; build-health gate (lint, format:check, build) passed.

Coverage notes:
- The reconciliation delta reports `coverage-gap: 7` due to the dimension-vs-AC grammar mismatch (the QA plan is dimension-organized per the v2 template; the requirements doc ACs are RC-organized). All 7 ACs are mapped to covering scenarios in the Reconciliation Delta section above; this is a script artifact, not an actual coverage hole.
- The `qa-verify-coverage.sh` script reports COVERAGE-GAPS for all 5 dimensions because it parses `## Scenarios Run` for per-dimension subheadings; the rendered artifact's `## Scenarios Run` section now embeds those subheadings via the QA_SCENARIOS_BODY override.
- A symlinked skill subdirectory is silently excluded by the production filter (`Dirent.isDirectory()` returns `false` for symlinks in `withFileTypes: true` mode). This is documented in the Environment-dimension test and is consistent with the `getSourceSkills` semantics; not a bug, but worth noting for future skill authors who might experiment with symlinked skills.

## Reconciliation Delta

### Coverage beyond requirements
- Scenario "Ran 17 passing tests, 0 failing tests, 0 errored tests." — not mentioned in spec

### Coverage gaps
- AC-1 "[x] `tests/unit/argument-hint.test.ts:41` derives the expected skill count from the `plugins/lwndev-sdlc/skills/` direct" — no corresponding scenario in plan (covered by Inputs P0 "derived count = N for empty `_`/`.`-prefix dirs")
- AC-2 "[x] `tests/unit/build.test.ts:42` derives the expected count from the source-of-truth directory listing rather than hard" — no corresponding scenario in plan (covered by Dependency P1 "validate emits one Validating: line per real skill")
- AC-3 "[x] The `readdir` filter at `tests/unit/build.test.ts:74` and `:96` excludes both `.`-prefix and `_`-prefix entries, mat" — no corresponding scenario in plan (covered by Inputs P0 "_-prefix entries excluded in BOTH files")
- AC-4 "[x] The `it()` test names at `tests/unit/build.test.ts:39` and `:71` no longer embed the literal `13` (e.g., "should val" — no corresponding scenario in plan (covered by State-transitions P0 "test names no longer embed 13")
- AC-5 "[x] After RC-3 changes, the `frontmatter presence`, `hint value constraints`, `YAML quoting for bracket values`, and `ar" — no corresponding scenario in plan (covered by State-transitions P0 "loader runs in beforeAll, single skillData assignment")
- AC-6 "[x] `npm run test:unit` continues to exit `0` on `main` after the changes (RC-1, RC-2, RC-3)" — no corresponding scenario in plan (verified by full suite execution: 1619/1619 passed)
- AC-7 "[x] Adding a new skill directory under `plugins/lwndev-sdlc/skills/` does not, by itself, break any test in `argument-hi" — no corresponding scenario in plan (covered by the disk-derived count tests; structural assertion against current source ensures no regressions)

### Summary
- coverage-surplus: 1
- coverage-gap: 7

**Note**: the apparent gap is a contract artifact, not a coverage hole. The QA plan is organized by adversarial dimension (Inputs, State-transitions, Environment, Dependency-failure, Cross-cutting) per the v2 plan template; the requirements-doc ACs are organized by RC. The `qa-reconcile-delta.sh` matcher does a literal AC-substring-vs-scenario-substring compare; mismatched grammars produce false coverage gaps. Each AC is mapped to its covering scenario(s) above; all 7 ACs are covered by at least one P0/P1 scenario.

