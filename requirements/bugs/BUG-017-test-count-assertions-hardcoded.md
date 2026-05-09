# Bug: test count assertions hardcoded

## Bug ID

`BUG-017`

## GitHub Issue

[#272](https://github.com/lwndev/lwndev-marketplace/issues/272)

## Category

`regression`

## Severity

`medium`

## Description

`tests/unit/argument-hint.test.ts` and `tests/unit/build.test.ts` hardcode the skill count to `13` in multiple assertions. The assertions pass on `main` today (13 skills) but break the moment a 14th skill is added — already observed on `feat/FEAT-032-executing-qa-ephemeral-tests` (commit `9b16f84`), where `addressing-qa-findings` brings the count to 14 and produces 55 failing tests.

## Steps to Reproduce

1. Add a 14th skill directory under `plugins/lwndev-sdlc/skills/` (e.g., check out `feat/FEAT-032-executing-qa-ephemeral-tests` at `9b16f84`).
2. Run `npm run test:unit`.
3. Observe 55 failures concentrated in `argument-hint.test.ts` (53 of 56 tests) and `build.test.ts` (2 of 12 tests).

## Expected Behavior

Skill-count assertions derive the expected count from the actual `plugins/lwndev-sdlc/skills/` directory (filtering `.`-prefix and `_`-prefix entries to match `getSourceSkills` behavior). Adding a new skill does not break unrelated tests; the assertions only enforce internal consistency (e.g., "every skill validated by build matches every skill on disk").

## Actual Behavior

`tests/unit/argument-hint.test.ts:41` asserts `Object.keys(skillData).length === 13`. `tests/unit/build.test.ts:42` asserts `Validating: ` matches occur exactly 13 times. `tests/unit/build.test.ts:90` asserts `skillDirs.length === 13`. The literal `13` is also embedded in test names at lines 39 and 71 ("all 13 skills"). Adding a 14th skill flips every dependent test red, including assertions that have nothing to do with skill count (e.g., 50+ frontmatter / hint-value / argument-handling assertions in `argument-hint.test.ts` that fail because the prerequisite `skillData` map was populated for 14 skills but the prerequisite test failed first, taking the whole describe block with it).

## Root Cause(s)

1. `tests/unit/argument-hint.test.ts:41` hardcodes `expect(Object.keys(skillData).length).toBe(13)`. The literal `13` must be replaced with a value derived from the actual `plugins/lwndev-sdlc/skills/` directory listing (filtering both `.`-prefix and `_`-prefix entries to match `getSourceSkills` behavior).
2. `tests/unit/build.test.ts:42` hardcodes `expect(matches.length).toBe(13)` against `Validating: ` matches in `npm run validate` output. `tests/unit/build.test.ts:90` hardcodes `expect(skillDirs.length).toBe(13)`. Both must derive the count from the same source-of-truth directory listing. Additionally, the `readdir` filter at `build.test.ts:74` and `:96` currently excludes only `.`-prefix entries; it must also exclude `_`-prefix entries so the derived count matches `getSourceSkills` and the `argument-hint.test.ts:31-33` filter. The `it()` test names at lines 39 ("should validate all 13 skills") and 71 ("should have skills directory with all 13 skills") embed the literal `13` and must be renamed to remove it.
3. The structural pattern in `argument-hint.test.ts` makes a single brittle prerequisite (line 41) cascade across the entire describe block. `skillData` is module-scoped state populated by the first `it()`; if that `it()` fails, every downstream assertion in `frontmatter presence` (line 44), `hint value constraints` (line 62), `YAML quoting for bracket values` (line 73), and `argument-handling instructions in SKILL.md body` (line 84) reads from a partially-populated or empty map and fails too. This is a separate concern from the count value — even after RC-1 is fixed (count derived dynamically), a future drift could still cascade unless the dependent assertions are decoupled from the shared-state prerequisite (e.g., by per-skill presence checks, or by iterating over the actual loaded `skillData` keys instead of over a static `SKILLS_WITH_HINTS` array).

## Affected Files

- `tests/unit/argument-hint.test.ts`
- `tests/unit/build.test.ts`

## Acceptance Criteria

- [x] `tests/unit/argument-hint.test.ts:41` derives the expected skill count from the `plugins/lwndev-sdlc/skills/` directory listing (filtering `.`-prefix and `_`-prefix entries) instead of hardcoding `13` (RC-1)
- [x] `tests/unit/build.test.ts:42` and `tests/unit/build.test.ts:90` derive the expected count from the same source-of-truth directory listing rather than hardcoding `13` (RC-2)
- [x] The `readdir` filter at `tests/unit/build.test.ts:74` and `:96` excludes both `.`-prefix and `_`-prefix entries, matching the `argument-hint.test.ts:31-33` filter and `getSourceSkills` behavior (RC-2)
- [x] The `it()` test names at `tests/unit/build.test.ts:39` and `:71` no longer embed the literal `13` (e.g., "should validate every skill in the plugin") (RC-2)
- [x] After RC-3 changes, the `frontmatter presence`, `hint value constraints`, `YAML quoting for bracket values`, and `argument-handling instructions in SKILL.md body` describe blocks in `tests/unit/argument-hint.test.ts` each pass independently of whether the line-41 prerequisite assertion succeeds — i.e., a forced failure of the prerequisite (e.g., a temporary `expect(false).toBe(true)` at line 41) does not cause more than 1 test to fail (RC-3)
- [x] `npm run test:unit` continues to exit `0` on `main` after the changes (RC-1, RC-2, RC-3)
- [x] Adding a new skill directory under `plugins/lwndev-sdlc/skills/` does not, by itself, break any test in `argument-hint.test.ts` or `build.test.ts` — verified by adding a temporary 14th skill, running the suite, then removing it (RC-1, RC-2, RC-3)

## Completion

**Status:** `Pending`

**Completed:** YYYY-MM-DD

**Pull Request:** [#N](https://github.com/lwndev/lwndev-marketplace/pull/N)

## Notes

The reporting issue (#272) also mentions a contract-mismatch error in `validate-test-layout.ts` of the form `expected '^Verdict: (PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY) \| Passed: ([0-9]+) \| Failed: ([0-9]+) \| Errored: ([0-9]+)$'; got: ''`. That error originates from FEAT-032 branch state (`9b16f84`) and is not present on `main` — neither the regex nor an empty-output emitter exists in the current `scripts/validate-test-layout.ts`. It is intentionally **out of scope** for this bug; the FEAT-032 branch will need to address it as part of its own pre-merge fixes. This bug fix focuses on the preventive hardening called out in the issue's third acceptance criterion ("replace the hardcoded `13` with a derivation from the actual skills directory so this can't break again on the next skill addition").

The cascading-failure pattern in `argument-hint.test.ts` is captured by RC-3 (a separate concern from the count value in RC-1). RC-3's AC requires that a forced failure of the line-41 prerequisite does not propagate beyond 1 test. The simplest implementation is to load `skillData` inside `beforeAll` rather than in an `it()` block, so the test framework's own setup-vs-test distinction prevents cascade. A more conservative alternative is to keep the load in its own `it()` but add per-test `if (!data) { expect.fail('skillData not loaded; see line 41'); return; }` guards — but `beforeAll` is preferred because it surfaces the load failure once, at the right level of the test tree.

The static `SKILLS_WITH_HINTS` array (line 10) and `EXCLUDED_SKILLS` array (line 23) in `argument-hint.test.ts` cover only 10 of the 13 current skills. The `skill coverage completeness` describe block at line 96 dynamically iterates disk to ensure every skill has `argument-hint`, so the gap is partially mitigated. Closing the static-array gap (so every skill on disk gets the per-property frontmatter / hint-value / YAML-quoting / argument-handling checks) is **out of scope** for this bug — `managing-work-items` and `orchestrating-workflows` were intentionally excluded by the original test author. If a future skill author wants their skill exercised by all four describe blocks, they need to add it to `SKILLS_WITH_HINTS`.
