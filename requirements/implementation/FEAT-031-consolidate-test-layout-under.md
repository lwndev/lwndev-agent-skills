# Implementation Plan: Consolidate test layout under tests/ with enforcement

## Overview

FEAT-031 collapses the repo's two divergent test trees (TS under `scripts/__tests__/`, Bats under `plugins/lwndev-sdlc/.../tests/`) into a single `tests/` root with runner-scoped leaves (`tests/unit/` for Vitest, `tests/bats/` for Bats), unifies `npm test` to drive both runners, and lands a validator + PreToolUse hook so misplaced test files cannot regress the layout. The migration ships in six phases that mirror NFR-6's commit-per-phase guidance: Vitest relocation -> Bats relocation -> config/npm-script updates -> validator -> hook -> doc alignment + payload verification.

The build order is sequenced for review/revert isolation: each relocation phase is a mechanical move (with documented sed rewrites for Bats path resolution per FR-3) that keeps the existing test suite green at every commit boundary; the config phase (Phase 3) flips Vitest's `testMatch` and adds `tsconfig.test.json` / ESLint / `npm test` wiring **after** the files have already moved, so no file is ever orphaned from a runner; the validator (Phase 4) and hook (Phase 5) land **after** the layout is correct, so they do not block their own enabling commits; doc alignment + plugin-install payload verification (Phase 6) closes the loop. The shared `scripts/test-layout-rules.ts` module (Edge Case 5) lands in Phase 4 alongside the validator and is consumed by the hook in Phase 5 — single source of truth for both tools' allow-rule and rule IDs.

Phases 1, 2, 3, 4, and 6 carry `**ComplexityOverride:** opus` clamps by intent: NFR-6 mandates one commit per phase boundary (Vitest relocation; Bats relocation; config + npm-script updates; validator; hook; doc alignment) so the relocation is reviewable and revertible as a single unit per logical step. Splitting any of these phases would violate NFR-6 — Phase 1 must move all 51 TS files in one commit (otherwise `vitest.config.ts` `testMatch` flips against a partially-moved tree), Phase 2 must move all 68 Bats files in one commit (otherwise `npm test:bats` flips against a partial set), Phase 3 must land the five interlocking config edits together (otherwise `npm test`, ESLint, and `tsconfig.test.json` are mutually inconsistent at intermediate commits), Phase 4 must land the validator and its rule module together (otherwise the validator has no allow-rule to import), and Phase 6 must land the doc audit and the FR-12 install verification together (otherwise the verification runs against a tree with stale doc guidance). Phase 5 (hook) stays within the per-phase budget without a clamp.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-031 | [#255](https://github.com/lwndev/lwndev-marketplace/issues/255) | [FEAT-031-consolidate-test-layout-under.md](../features/FEAT-031-consolidate-test-layout-under.md) | Medium | Medium | Pending |

## Recommended Build Sequence

### Phase 1: Vitest TS test relocation (FR-2)

**Feature:** [FEAT-031](../features/FEAT-031-consolidate-test-layout-under.md) | [#255](https://github.com/lwndev/lwndev-marketplace/issues/255)
**Status:** ✅ Complete
**Depends on:** none
**ComplexityOverride:** opus

#### Rationale

Move first, configure second. Phase 1 relocates every TS test file (42 `.test.ts` + 8 non-fixture `.spec.ts` + 1 root-level `.spec.ts`) into `tests/unit/` and the `qa-fixture/` shared fixture into `tests/fixtures/`, but does **not** flip `vitest.config.ts` `testMatch` yet. The migration window uses a transitional dual-include `testMatch: ['**/__tests__/**/*.test.ts', 'tests/unit/**/*.test.ts']` so the moved files keep running under the same single `npm test` invocation; the final narrowing to `['tests/unit/**/*.test.ts']` happens in Phase 3 once every TS file has moved. NFR-1 (zero-loss) is verified at this commit boundary by capturing pre-/post-move Vitest test counts.

The two stay-in-place exceptions documented in FR-2 are honored: `scripts/__tests__/fixtures/feat-030-known-buggy/` (with its `.spec.ts` fixture) and `scripts/__tests__/fixtures/qa-fixture-empty/` remain at their existing paths because the `feat-030-executing-qa.test.ts` harness invokes the fixture's own `vitest.config.ts` as a child process and `qa-integration.test.ts` references the empty-fixture README path — moving either would force a harness rewrite for no migration benefit. Edge Case 3's `qa-fixture` harness consumers (`qa-integration.test.ts`, `qa-dependency-failure-BUG-012.test.ts`, `qa-inputs-BUG-012.test.ts`) get their fixture path references updated in this phase.

#### Implementation Steps

1. Create the new directory structure: `tests/unit/`, `tests/fixtures/`. The `tests/bats/` tree is created in Phase 2.
2. Move all 42 `.test.ts` files from `scripts/__tests__/*.test.ts` to `tests/unit/`. Preserve filenames (already kebab-case, already `.test.ts`). Use `git mv` so history follows.
3. Move the 8 non-fixture `.spec.ts` files from `scripts/__tests__/` to `tests/unit/` while renaming to `.test.ts` and applying kebab-case per the FEAT-031 inventory rename table: `qa-CHORE-034.spec.ts` -> `qa-chore-034.test.ts`; `qa-CHORE-035.spec.ts` -> `qa-chore-035.test.ts`; `qa-FEAT-020.spec.ts` -> `qa-feat-020.test.ts`; `qa-FEAT-021.spec.ts` -> `qa-feat-021.test.ts`; `qa-FEAT-022.spec.ts` -> `qa-feat-022.test.ts`; `qa-feat-029.spec.ts` -> `qa-feat-029.test.ts`; `qa-finalizing-workflow-inputs.spec.ts` -> `qa-finalizing-workflow-inputs.test.ts`. Move the root-level `__tests__/qa-feat-030-contract.spec.ts` to `tests/unit/qa-feat-030-contract.test.ts`. Remove the now-empty root `__tests__/` directory.
4. Move `scripts/__tests__/fixtures/qa-fixture/` to `tests/fixtures/qa-fixture/`. Update fixture-path references in `scripts/__tests__/qa-integration.test.ts`, `scripts/__tests__/qa-dependency-failure-BUG-012.test.ts`, and `scripts/__tests__/qa-inputs-BUG-012.test.ts` from `scripts/__tests__/fixtures/qa-fixture/` to `tests/fixtures/qa-fixture/` (Edge Case 3). Note: those three harness files just moved to `tests/unit/` in step 2; apply the path edits at the new locations.
5. Apply transitional dual-include in `vitest.config.ts`: `testMatch: ['**/__tests__/**/*.test.ts', 'tests/unit/**/*.test.ts']`. Keep the existing `exclude` rule for `scripts/__tests__/fixtures/feat-030-known-buggy/`. This is reverted to the final narrow `['tests/unit/**/*.test.ts']` in Phase 3.
6. Run `npm test 2>&1 | tee /tmp/feat-031-phase1-test.log` and confirm Vitest test count + pass/fail summary match the pre-feature baseline captured on `main` (NFR-1). Run `npm run validate` to confirm plugin-manifest validation still passes.
7. Commit with message `refactor(tests): relocate Vitest TS tests to tests/unit/ (FEAT-031 phase 1)`.

#### Deliverables

- [x] `tests/unit/` (42 moved `.test.ts` files preserving filenames + 7 renamed-and-moved spec files + 1 root-level renamed-and-moved spec file = 50 files)
- [x] `tests/fixtures/qa-fixture/` (relocated from `scripts/__tests__/fixtures/qa-fixture/`)
- [x] `scripts/__tests__/` reduced to fixture-only (`fixtures/feat-030-known-buggy/`, `fixtures/qa-fixture-empty/`, `fixtures/feat-014/`)
- [x] Repo-root `__tests__/` directory removed
- [x] `vitest.config.ts` (transitional dual-include `testMatch`)
- [x] Updated fixture-path references in `tests/unit/qa-integration.test.ts`, `tests/unit/qa-dependency-failure-BUG-012.test.ts`, `tests/unit/qa-inputs-BUG-012.test.ts`

---

### Phase 2: Bats test relocation (FR-3)

**Feature:** [FEAT-031](../features/FEAT-031-consolidate-test-layout-under.md) | [#255](https://github.com/lwndev/lwndev-marketplace/issues/255)
**Status:** Pending
**Depends on:** Phase 1
**ComplexityOverride:** opus

#### Rationale

Phase 2 moves all 68 `.bats` files out of `plugins/lwndev-sdlc/{scripts,skills/<skill>/scripts}/tests/` into `tests/bats/{shared,shared/hooks,skills/<skill>}/`. Helper scripts stay at their runtime paths under `plugins/` — only the test files move. The relocation changes the relative depth from each `.bats` file to its target script, so every `BATS_TEST_DIRNAME`-anchored path expression must be rewritten per FR-3's replacement table. Two scoped sed passes handle the two leaves: shared (top-level + hooks), and per-skill (one pass per skill subdirectory because the per-skill segment is a literal substitution in the replacement). FEAT-031 inventory verified across all 68 files that none use `load` directives — the rewrite is exclusively `BATS_TEST_DIRNAME` path expressions.

Phase 2 depends on Phase 1 because the unified `tests/` root must already exist (Phase 1 created `tests/unit/` and `tests/fixtures/`) and the existing test suite must be green from the Phase-1 boundary so any Bats failure in Phase 2 is unambiguously a path-rewrite issue, not a Vitest collateral. Bats coverage gain is recorded separately (Bats was never invoked from `npm test` pre-feature; the count is informational, not subject to NFR-1's no-loss check).

#### Implementation Steps

1. Create `tests/bats/shared/`, `tests/bats/shared/hooks/`, and `tests/bats/skills/<skill>/` directories — one per skill that has a `scripts/tests/` directory under `plugins/lwndev-sdlc/skills/`.
2. Move the 14 top-level shared `.bats` files from `plugins/lwndev-sdlc/scripts/tests/*.bats` to `tests/bats/shared/`. Move the 6 hook `.bats` files from `plugins/lwndev-sdlc/scripts/tests/hooks/*.bats` to `tests/bats/shared/hooks/`. Use `git mv`.
3. For each skill under `plugins/lwndev-sdlc/skills/<skill>/scripts/tests/`, move the `.bats` files to `tests/bats/skills/<skill>/`. Eight skills are affected per the FEAT-031 inventory: `creating-implementation-plans` (6), `documenting-bugs` (1), `executing-qa` (9), `finalizing-workflow` (6), `implementing-plan-phases` (6), `managing-work-items` (6), `orchestrating-workflows` (8), `reviewing-requirements` (6). Total: 48 skill-level files.
4. Apply scoped sed rewrites for the shared leaf — files now under `tests/bats/shared/` (and `tests/bats/shared/hooks/`) — substituting `${BATS_TEST_DIRNAME}/..` with `${BATS_TEST_DIRNAME}/../../../plugins/lwndev-sdlc/scripts` per FR-3's replacement table. Hook-leaf files use the same shared replacement because they were originally under `plugins/lwndev-sdlc/scripts/tests/hooks/` (both old leaves resolved to `plugins/lwndev-sdlc/scripts/`). Run an additional pass for any `${BATS_TEST_DIRNAME}/../..` form (one extra `..` for the hooks subdirectory) to substitute the same parent-of-hooks anchor.
5. Apply per-skill sed rewrites for skill-leaf files — for each skill, files under `tests/bats/skills/<skill>/` substitute `${BATS_TEST_DIRNAME}/..` with `${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/<skill>/scripts`. The `<skill>` segment is literal per file location; iterate per-skill so the substitution stays scoped.
6. Delete the now-empty `plugins/lwndev-sdlc/scripts/tests/` and `plugins/lwndev-sdlc/scripts/tests/hooks/` directories. Delete the now-empty `plugins/lwndev-sdlc/skills/<skill>/scripts/tests/` directories per skill (Edge Case 8). `git status` should show only file moves and the directory deletions.
7. Run `bats tests/bats` (recursive). Confirm zero failures. Bats discovers all 68 files; broken path rewrites fail fast at test discovery time (Edge Case 2). If any failures surface, inspect the offending file's `BATS_TEST_DIRNAME`-anchored expressions and fix the sed substitution.
8. Run `npm test 2>&1 | tee /tmp/feat-031-phase2-test.log` to confirm Vitest still green (Bats remains separate from `npm test` until Phase 3). Run `npm run validate` to confirm plugin validation still passes (no `.bats` files under `plugins/` anymore — payload reduction preview).
9. Commit with message `refactor(tests): relocate Bats tests to tests/bats/ (FEAT-031 phase 2)`.

#### Deliverables

- [ ] `tests/bats/shared/*.bats` (14 top-level shared files, paths rewritten)
- [ ] `tests/bats/shared/hooks/*.bats` (6 hook files, paths rewritten)
- [ ] `tests/bats/skills/creating-implementation-plans/*.bats` (6 files, paths rewritten)
- [ ] `tests/bats/skills/documenting-bugs/*.bats` (1 file, paths rewritten)
- [ ] `tests/bats/skills/executing-qa/*.bats` (9 files, paths rewritten)
- [ ] `tests/bats/skills/finalizing-workflow/*.bats` (6 files, paths rewritten)
- [ ] `tests/bats/skills/implementing-plan-phases/*.bats` (6 files, paths rewritten)
- [ ] `tests/bats/skills/managing-work-items/*.bats` (6 files, paths rewritten)
- [ ] `tests/bats/skills/orchestrating-workflows/*.bats` (8 files, paths rewritten)
- [ ] `tests/bats/skills/reviewing-requirements/*.bats` (6 files, paths rewritten)
- [ ] Removed `plugins/lwndev-sdlc/scripts/tests/` (empty, deleted)
- [ ] Removed per-skill `plugins/lwndev-sdlc/skills/<skill>/scripts/tests/` (empty, deleted)

---

### Phase 3: Config + npm-script updates (FR-4, FR-5, FR-6, FR-7, FR-8)

**Feature:** [FEAT-031](../features/FEAT-031-consolidate-test-layout-under.md) | [#255](https://github.com/lwndev/lwndev-marketplace/issues/255)
**Status:** Pending
**Depends on:** Phase 2
**ComplexityOverride:** opus

#### Rationale

With every test file at its final location, Phase 3 finalizes the configs that point to those locations: Vitest narrows `testMatch` to the final `tests/unit/**/*.test.ts`; a new `tsconfig.test.json` extends the base tsconfig with `include: ["tests/**/*.ts"]`; ESLint's `parserOptions.project` references both tsconfigs; `lint`/`format`/`lint-staged` globs widen to `scripts/ tests/`; `bats` lands as an npm devDependency pinned to `^1.10.0`; and `package.json`'s `test` script becomes `npm run test:unit && npm run test:bats` so a single `npm test` invocation drives both runners and exits non-zero if either fails. This is the first commit at which Bats is exercised by `npm test`.

Bundling FR-4 through FR-8 into one phase is intentional: each is a single config-file edit with no cross-file dependency, and splitting them would produce per-step interim states where (e.g.) `tsconfig.test.json` exists but ESLint doesn't reference it, or `test:bats` exists but `test` doesn't chain to it. The phase is small in step count and file count (one edit per FR) but spans config surfaces — within budget per the per-phase complexity table when counted as five small edits + a `npm install` and a runtime verification.

#### Implementation Steps

1. Narrow `vitest.config.ts` `testMatch` from the Phase-1 transitional dual-include to `['tests/unit/**/*.test.ts']` (FR-4). Update `coverage.include` to `['scripts/**/*.ts']` and `coverage.exclude` to include `['tests/**', '**/*.test.ts', 'scripts/__tests__/fixtures/feat-030-known-buggy/**']` reflecting the new layout while preserving the Phase-1 fixture exclusion.
2. Create `tsconfig.test.json` extending `tsconfig.json` with `include: ["tests/**/*.ts"]` (FR-5). Confirm root `tsconfig.json` keeps `rootDir: "./scripts"` and `include: ["scripts/**/*.ts"]` unchanged.
3. Update `eslint.config.js` `parserOptions.project` to `['./tsconfig.json', './tsconfig.test.json']` (FR-6). Widen `package.json`'s `lint` and `format` globs to include `tests/**` (e.g., `eslint scripts/ tests/` and `prettier --write scripts/ tests/`). Widen `lint-staged` glob to include `tests/**/*.ts`.
4. Run `npm install --save-dev bats` (FR-7) to add the npm `bats` devDependency. Verify the installed version is in the 1.x line; pin to `^1.10.0` (or higher caret if `npm view bats version` reports a higher 1.x). Confirm `node_modules/.bin/bats` resolves and `npx bats --version` returns the expected 1.x version.
5. Add `package.json` scripts `test:unit` (`vitest run`) and `test:bats` (`npx bats tests/bats`). Rewrite `test` to `npm run test:unit && npm run test:bats` (FR-8). Leave `test:watch`, `test:coverage`, and `test-skill` unchanged (NFR-2).
6. Run `npm test` and confirm both runners execute and the exit code is 0. Capture the runtime to verify NFR-4 (under 2x the pre-feature Vitest-only runtime). If exceeded, investigate before merging.
7. Run `npm run lint`, `npm run format:check`, and `npm run validate` to confirm the wider globs and updated parser config do not introduce false positives. Confirm `npm run test:watch` still exits cleanly when interrupted (NFR-2 spot-check). Confirm `npm run test-skill` still works against an arbitrary skill fixture (NFR-2 spot-check).
8. Commit with message `chore(tests): finalize Vitest+Bats config and unify npm test (FEAT-031 phase 3)`.

#### Deliverables

- [ ] `vitest.config.ts` (final `testMatch`, updated `coverage.include`/`coverage.exclude`)
- [ ] `tsconfig.test.json` (new, extends base)
- [ ] `eslint.config.js` (references both tsconfigs)
- [ ] `package.json` (added `bats` devDep, added `test:unit`/`test:bats`, rewrote `test`, widened `lint`/`format`/`lint-staged` globs)
- [ ] `package-lock.json` (regenerated by `npm install`)

---

### Phase 4: Layout validator + shared rule module (FR-9, Edge Case 5)

**Feature:** [FEAT-031](../features/FEAT-031-consolidate-test-layout-under.md) | [#255](https://github.com/lwndev/lwndev-marketplace/issues/255)
**Status:** Pending
**Depends on:** Phase 3
**ComplexityOverride:** opus

#### Rationale

Phase 4 lands the validator that prevents future regression of the Phase 1-3 layout. The validator is a TS script (`scripts/validate-test-layout.ts`) that walks the working tree and emits a normative-rule-keyed line per violation. The rule IDs (`ts-outside-tests-unit`, `spec-extension-disallowed`, `bats-outside-tests-bats`) and the single allow-rule path (the `feat-030-known-buggy` fixture's `.spec.ts`) live in `scripts/test-layout-rules.ts` so the validator and Phase 5's hook share one source of truth (Edge Case 5 — split state would let one tool block work the other generates).

Wiring the validator into `npm run validate` and `.husky/pre-commit` happens in this phase: `package.json`'s `validate` script becomes `tsx scripts/validate-test-layout.ts && tsx scripts/build.ts` so a layout failure short-circuits before manifest validation, and `.husky/pre-commit` appends `npm run validate` after the existing chain (FEAT-031 inventory rationale: `lint-staged` scopes to staged files only; the validator must scan the whole tree). Phase 4 depends on Phase 3 because the validator's clean-tree path requires the post-Phase-2 layout already in place — running the validator on a pre-relocation tree would fire on every existing test file.

#### Implementation Steps

1. Write `scripts/test-layout-rules.ts` exporting: rule IDs (`RULE_TS_OUTSIDE_TESTS_UNIT = 'ts-outside-tests-unit'`, `RULE_SPEC_EXTENSION_DISALLOWED = 'spec-extension-disallowed'`, `RULE_BATS_OUTSIDE_TESTS_BATS = 'bats-outside-tests-bats'`); `ALLOWED_FIXTURE_PATHS` array containing the single allow-rule path (`scripts/__tests__/fixtures/feat-030-known-buggy/__tests__/qa-buggy.spec.ts`); a `classifyPath(filePath: string): { rule: string } | null` helper that returns the rule that fired (or `null` if the path is allowed). The classifier short-circuits on non-test paths (paths that don't match `*.test.ts`, `*.spec.ts`, or `*.bats`) so it is safe to call from a hot-path hook.
2. Write `scripts/validate-test-layout.ts`: walks `scripts/`, `plugins/`, `tests/`, and the repo root via `glob` (or `fs.readdir` recursive); for each candidate file, calls `classifyPath`; emits one `[validate-test-layout] FAIL: <path> -> rule=<rule>` line per violation; trailing `<N> violations` summary; exits non-zero on any violation, zero on a clean tree. The exact output format matches the requirements doc Output Format example.
3. Write `tests/unit/validate-test-layout.test.ts` (Vitest): clean tree returns exit 0 with no violations; misplaced `.test.ts` outside `tests/unit/` fires `ts-outside-tests-unit`; any `.spec.ts` outside the fixture allow-rule fires `spec-extension-disallowed`; the fixture path passes (allow-rule); misplaced `.bats` outside `tests/bats/` fires `bats-outside-tests-bats`; exit code 1 on violations, 0 on clean. Drive the validator as a child process against synthetic fixture trees under `tmp` directories.
4. Wire validator into `package.json`'s `validate` script: rewrite to `tsx scripts/validate-test-layout.ts && tsx scripts/build.ts`. Confirm `build.ts` is unchanged — the layout validator runs as a separate process so a layout failure short-circuits the chain (FR-9).
5. Append `npm run validate` to `.husky/pre-commit` after the existing chain. Final hook order: `lint-staged -> lint -> format:check -> test -> audit -> validate` (NFR-3, FEAT-031 inventory).
6. Manually misplace a test file (e.g., copy `tests/unit/constants.test.ts` to `scripts/foo.test.ts`), run `npm run validate`, confirm the validator fires `ts-outside-tests-unit` against the misplaced path and exits non-zero. Revert the misplacement. Repeat with a `.spec.ts` and a `.bats` outside their roots to confirm the other two rules fire.
7. Run `npm test -- --testPathPatterns=validate-test-layout | tail -50`, then `npm test` (full), then `npm run validate` to confirm everything still passes on the clean tree.
8. Commit with message `feat(tests): add layout validator + shared rule module (FEAT-031 phase 4)`.

#### Deliverables

- [ ] `scripts/test-layout-rules.ts` (rule IDs, allow-rule constant, `classifyPath` helper)
- [ ] `scripts/validate-test-layout.ts` (validator entry point)
- [ ] `tests/unit/validate-test-layout.test.ts` (Vitest coverage per FR-9)
- [ ] `package.json` (`validate` script chains layout validator before build validator)
- [ ] `.husky/pre-commit` (`npm run validate` appended after audit)

---

### Phase 5: PreToolUse enforcement hook (FR-10, Edge Case 4)

**Feature:** [FEAT-031](../features/FEAT-031-consolidate-test-layout-under.md) | [#255](https://github.com/lwndev/lwndev-marketplace/issues/255)
**Status:** Pending
**Depends on:** Phase 4

#### Rationale

Phase 5 adds the project-scoped PreToolUse hook that blocks `Write`/`Edit` to misplaced test paths so test-generating skills (e.g., `executing-qa`) cannot regress the layout between commits. The hook reads the same rule IDs and allow-rule constant exported by Phase 4's `scripts/test-layout-rules.ts` — Edge Case 5's "either both honor the allow-rule or neither does" requirement is satisfied by direct module reuse, not by parallel hardcoding. Hook implementation lives at `scripts/hooks/validate-test-layout-hook.ts` (creating the directory) — **not** under `plugins/lwndev-sdlc/scripts/hooks/`, because plugin-internal hooks ship to `/plugin install` payloads via the marketplace which would contradict FR-10's project-scoped framing and undermine FR-12.

The hook receives a JSON payload on stdin (`tool_name`, `tool_input.file_path`); fails open on parse error (Edge Case 4) so a malformed payload never blocks legitimate work; short-circuits on non-test paths so the hook is essentially a no-op for the >99% of edits that aren't to test files. Rejection messages name the rule and the canonical destination so the model can self-correct. `.claude/settings.json` (the project-scoped, checked-in file — distinct from the gitignored `.claude/settings.local.json`) wires the hook with `matcher: "Write|Edit"`.

#### Implementation Steps

1. Create `scripts/hooks/` directory. Write `scripts/hooks/validate-test-layout-hook.ts`: reads stdin, parses JSON, extracts `tool_input.file_path`; on parse error or missing field, exits 0 (fail open per Edge Case 4); imports `classifyPath` from `scripts/test-layout-rules.ts`; if `classifyPath(file_path)` returns a rule, prints rejection message to stdout (e.g., `[validate-test-layout-hook] reject: <path> violates <rule>; canonical destination: tests/unit/ (or tests/bats/)`) and exits non-zero; otherwise exits 0. Hook accepts non-test paths as a fast no-op.
2. Add the hook entry to `.claude/settings.json` (project-scoped checked-in file): `hooks.PreToolUse[]` array entry with `matcher: "Write|Edit"`, `hooks: [{ type: "command", command: "tsx scripts/hooks/validate-test-layout-hook.ts" }]`. If `.claude/settings.json` does not exist yet (only `.claude/settings.local.json` exists per the FEAT-031 inventory), create it with the minimal `{ "hooks": { "PreToolUse": [...] } }` shape.
3. Write `tests/bats/shared/hooks/validate-test-layout-hook.bats`: rejects misplaced `*.test.ts` outside `tests/unit/`; rejects `*.spec.ts` (fixture excepted); rejects misplaced `*.bats` outside `tests/bats/`; allow-rule passes for the `feat-030-known-buggy` fixture; allows non-test edits (e.g., `*.md`, `*.ts` outside test names) as no-ops; **fails open on malformed `tool_input` JSON** (Edge Case 4) — feed the hook invalid JSON via stdin and assert exit 0 + no rejection message. Use the same fixture pattern as existing hook bats tests under `tests/bats/shared/hooks/`.
4. Run `bats tests/bats/shared/hooks/validate-test-layout-hook.bats` locally. Manually trigger the hook by attempting a `Write` to a synthetic misplaced path (e.g., `Write` `scripts/foo.test.ts`) in a development session — confirm the hook rejects with the rule + canonical-destination message, then revert.
5. Run `npm test`, then `npm run validate` to confirm zero regressions. Confirm the validator (Phase 4) and hook (Phase 5) both share the rule module — grep `import` lines to verify both files import from `scripts/test-layout-rules.ts`.
6. Commit with message `feat(tests): add PreToolUse layout-enforcement hook (FEAT-031 phase 5)`.

#### Deliverables

- [ ] `scripts/hooks/validate-test-layout-hook.ts` (PreToolUse hook entry point)
- [ ] `.claude/settings.json` (project-scoped checked-in file with `PreToolUse` `Write|Edit` matcher wired to the hook)
- [ ] `tests/bats/shared/hooks/validate-test-layout-hook.bats` (Bats coverage including Edge Case 4 fail-open)

---

### Phase 6: Documentation alignment + plugin install verification (FR-11, FR-12, NFR-5)

**Feature:** [FEAT-031](../features/FEAT-031-consolidate-test-layout-under.md) | [#255](https://github.com/lwndev/lwndev-marketplace/issues/255)
**Status:** Pending
**Depends on:** Phase 5
**ComplexityOverride:** opus

#### Rationale

Phase 6 closes the loop on documentation and verifies the plugin-install payload is clean. With code, configs, validator, and hook all landed, the docs that previously pointed contributors at the old layout (`scripts/__tests__/`, `.spec.ts` patterns, `__tests__/qa-<dimension>.spec.ts (or .test.ts)`) must be rewritten to the new layout — otherwise the next contributor reads stale guidance and authors a misplaced test that the validator and hook then block, causing avoidable churn. CLAUDE.md gets the §3 Skill Authoring update; `executing-qa/SKILL.md` gets the line ~178 rewrite to `tests/unit/qa-<dimension>.test.ts`; every other `SKILL.md` is audited for `__tests__/` or `.spec.ts` mentions.

Plugin-install payload verification (FR-12) ships in this phase as a manual acceptance step: install the plugin against a fresh Claude config and confirm `find <plugin-install-path> -type f \( -name '*.bats' -o -name '*.test.ts' -o -name '*.spec.ts' \)` returns empty. This is the NFR-5 payload-reduction success metric. The marketplace `source` path already points at `./plugins/lwndev-sdlc` and Phase 2 emptied that subtree of tests, so no `marketplace.json` edit is required (Edge Case 7); the install verification is the proof that Phase 2's relocation actually achieved payload reduction. Contributor `npx bats <path>` documentation also lands here per FR-7.

#### Implementation Steps

1. Update `CLAUDE.md` "Skill Authoring: Prefer Scripts Over Prose" section §3 ("Every script behavior needs bats coverage") to read: "TS modules -> Vitest under `tests/unit/`; shell scripts -> Bats under `tests/bats/{shared,skills/<skill>}/`. New test files land at the canonical leaf or the validator/hook (Phase 4/5 of FEAT-031) blocks the commit." Add a "Running tests locally" subsection (or update the existing `npm test` documentation) to include `npx bats tests/bats` for shell-only iteration and reference the contributor-install path of the `bats` npm devDep (FR-7).
2. Update `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` line ~178: replace the `vitest / jest: __tests__/qa-<dimension>.spec.ts (or .test.ts per project config)` bullet with `vitest / jest: tests/unit/qa-<dimension>.test.ts`. Drop the parenthetical extension confusion. Apply Caveman Lite prose per the repo's authoring convention; load-bearing carve-outs (error messages, contract lines) stay verbatim.
3. Audit every other `SKILL.md` under `plugins/lwndev-sdlc/skills/` for `__tests__/` or `.spec.ts` mentions: `grep -rn '__tests__\|\.spec\.ts' plugins/lwndev-sdlc/skills/`. For each hit, update to the new layout (`tests/unit/`, `.test.ts`) or remove the stale mention. Specific files to check (non-exhaustive): `documenting-qa/SKILL.md`, `executing-bug-fixes/SKILL.md`, `reviewing-requirements/SKILL.md`, and any `references/` docs that mention test paths.
4. Run `npm test`, then `npm run validate` to confirm the doc edits do not break plugin validation.
5. Manually verify the plugin-install payload (FR-12, NFR-5): on a fresh Claude config (or `CLAUDE_CONFIG_DIR` override pointing to a temporary directory), run `/plugin marketplace add lwndev/lwndev-marketplace` and `/plugin install lwndev-sdlc@lwndev-plugins`; then `find <plugin-install-path> -type f \( -name '*.bats' -o -name '*.test.ts' -o -name '*.spec.ts' \)` and confirm empty. Capture the `du -sh <plugin-install-path>` before/after numbers for the PR description (NFR-5). Document the verification command and result in the PR body.
6. Run the full pre-/post-feature comparison for NFR-1 + NFR-4: capture `npm test 2>&1 | tee /tmp/feat-031-final-test.log` on the feature branch and diff Vitest test counts against the baseline captured on `main` at Phase 1 start. Document the post-feature `npm test` runtime vs. the pre-feature Vitest-only runtime in the PR description (NFR-4 acceptance).
7. Confirm acceptance: every acceptance-criteria checkbox in the requirements doc passes against the working tree; the PR body includes the NFR-1 count comparison, NFR-4 runtime comparison, and NFR-5 payload comparison.
8. Commit with message `docs(tests): align skill docs with new tests/ layout (FEAT-031 phase 6)`.

#### Deliverables

- [ ] `CLAUDE.md` (§3 Skill Authoring rewrite + contributor `npx bats` documentation per FR-7)
- [ ] `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` (line ~178 rewrite)
- [ ] Audited `plugins/lwndev-sdlc/skills/<skill>/SKILL.md` files (any with `__tests__/` or `.spec.ts` mentions updated)
- [ ] PR description with NFR-1 test-count comparison, NFR-4 runtime comparison, NFR-5 payload-size comparison, and FR-12 install-verification proof

---

## Shared Infrastructure

- `scripts/test-layout-rules.ts` (Phase 4) is the single source of truth for rule IDs (`ts-outside-tests-unit`, `spec-extension-disallowed`, `bats-outside-tests-bats`) and the `feat-030-known-buggy` fixture allow-rule. Both `scripts/validate-test-layout.ts` (Phase 4) and `scripts/hooks/validate-test-layout-hook.ts` (Phase 5) import from this module — Edge Case 5's split-state risk is eliminated by direct reuse.
- `tests/fixtures/qa-fixture/` (Phase 1) is the single canonical location for the shared QA harness fixture. Three Vitest harness files (now under `tests/unit/`) reference it.
- Phase 1's transitional dual-include `testMatch` is the only intentional cross-phase coupling: it exists because Phase 2 needs to land before Phase 3 narrows the glob, and a single `npm test` invocation must continue to discover the moved files at every commit boundary. Reverted in Phase 3.

## Testing Strategy

**Unit (Vitest)**: Phase 4 ships `tests/unit/validate-test-layout.test.ts` covering the validator's clean-tree, three-rule, allow-rule, and exit-code paths. All 51 existing TS tests continue to run from `tests/unit/` after Phase 1.

**Unit (Bats)**: Phase 5 ships `tests/bats/shared/hooks/validate-test-layout-hook.bats` covering the hook's three reject paths, allow-rule, non-test-no-op path, and Edge Case 4 fail-open. All 68 existing Bats tests continue to run from `tests/bats/` after Phase 2 (and now run via `npm test` after Phase 3 — first time pre-commit / CI exercises them).

**Integration**: Phase 6 manually verifies `npm test` on a fresh checkout exits 0 with both runners executing, `npm run validate` passes including layout validator, and the PreToolUse hook fires correctly against synthetic `tool_input.file_path` payloads (the bats suite covers the hook unit-side; the manual smoke test covers the live wiring).

**Acceptance (NFR-1, NFR-4, NFR-5)**: Phase 1 captures the pre-feature Vitest baseline on `main` for NFR-1 zero-loss verification. Phase 6 captures the post-feature counts and runtimes for the comparison. The plugin-install payload verification (FR-12) is the NFR-5 acceptance proof.

## Dependencies and Prerequisites

- **New devDep**: `bats` (npm package, `^1.10.0` caret pin per FR-7). Wraps bats-core; surfaces the version pin in `package-lock.json`.
- **Existing tools** (no version changes): Vitest, ESLint, Husky, lint-staged, Prettier, `tsx` (for running TS scripts), `npm`.
- **Existing scripts referenced**: `scripts/build.ts` (called after the layout validator in `npm run validate`); `scripts/__tests__/fixtures/feat-030-known-buggy/vitest.config.ts` (stay-in-place harness child config — touched only via the validator allow-rule).
- **No production dependencies added**.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Bats path-resolution rewrite (FR-3) breaks one or more `.bats` files because a rare expression form (e.g., `${BATS_TEST_DIRNAME}/../../some-helper`) is missed by the scoped sed passes | High | Med | Phase 2 runs `bats tests/bats` immediately after the move; broken paths fail fast at test discovery time (Edge Case 2). FEAT-031 inventory confirmed no `load` directives across all 68 files, so the rewrite surface is bounded to `BATS_TEST_DIRNAME` expressions. If a non-standard expression slips through, fix it in the same Phase 2 commit. |
| `vitest.config.ts` transitional dual-include (Phase 1) accidentally double-discovers a moved file under both globs, causing duplicate-test-run failures | Med | Low | After Phase 1's move, `scripts/__tests__/` retains only fixture subdirectories; the `**/__tests__/**/*.test.ts` glob no longer matches anything under `scripts/__tests__/` because the `.test.ts` files have all moved. Phase 1 step 6 verifies test count against baseline; a duplicate would surface as a count mismatch. Phase 3 narrows to the single glob. |
| `tsconfig.test.json` collides with the root `tsconfig.json`'s `rootDir: "./scripts"` constraint, breaking ESLint type-aware rules on the new test files | Med | Med | `tsconfig.test.json` extends the base but overrides `include` to `["tests/**/*.ts"]` and does **not** override `rootDir` (relying on the extended value). If type-aware rules surface errors, set `rootDir` in the test tsconfig to a parent directory or split it from `rootDir` constraint. Phase 3 step 7 catches via `npm run lint`. |
| Husky pre-commit chain (NFR-3) adds visible latency to every commit because `npm run validate` walks the whole tree | Low | Med | The validator short-circuits on non-test extensions; the walk over `scripts/`, `plugins/`, and `tests/` is cheap on a repo this size (low thousands of files). If latency is unacceptable, restrict the validator's walk roots or add `--changed` mode (out of scope unless measured). |
| PreToolUse hook (FR-10) blocks a legitimate edit because the path classifier mis-fires on a fixture file outside the documented allow-rule | High | Low | `classifyPath` returns null for non-test extensions; the only extensions that can fire are `.test.ts`, `.spec.ts`, `.bats` — and Edge Case 4's fail-open ensures parse errors never block. Phase 5 bats covers each rule + the allow-rule + non-test no-op explicitly. If a new fixture pattern emerges later, extend `ALLOWED_FIXTURE_PATHS` in `test-layout-rules.ts` (single edit, both tools pick it up). |
| `bats` npm package version drifts onto a major-bumped 2.x line and `^1.10.0` caret silently misses the new major | Low | Low | Caret `^1.10.0` constrains updates to the 1.x line by definition. `npm audit` and `package-lock.json` review at install time surface the resolved version. Future major-version bumps require an explicit caret bump. |
| Plugin-install payload verification (FR-12) fails because a `.test.ts` or `.spec.ts` file slipped under `plugins/` post-Phase-1 | High | Low | The Phase 4 validator and Phase 5 hook both block this regression at commit and at runtime. Phase 6 step 5 is the explicit empirical check; if it fails, the validator/hook combo missed a rule and that's a Phase 4/5 defect, fixed by extending the rule set. |

## Success Criteria

- Phase 1: All 42 `.test.ts` files moved to `tests/unit/`; all 8 non-fixture `.spec.ts` files renamed and moved; root `__tests__/qa-feat-030-contract.spec.ts` moved; `qa-fixture/` relocated to `tests/fixtures/`; pre-/post-Phase-1 Vitest test count matches; `npm test` and `npm run validate` clean.
- Phase 2: All 68 `.bats` files moved to `tests/bats/{shared,shared/hooks,skills/<skill>}/`; `BATS_TEST_DIRNAME`-anchored expressions rewritten per FR-3 replacement table; `bats tests/bats` passes; old `tests/` directories under `plugins/` deleted; `npm test` (Vitest still alone) clean; `npm run validate` clean.
- Phase 3: `vitest.config.ts` `testMatch` is `['tests/unit/**/*.test.ts']`; `tsconfig.test.json` exists and extends base; ESLint references both tsconfigs; `package.json` has `bats` devDep, `test:unit`/`test:bats` scripts, and `test` chains both runners; `npm test` exits 0 with both runners executing; runtime under 2x the pre-feature Vitest-only runtime.
- Phase 4: `scripts/test-layout-rules.ts` exports rule IDs and `ALLOWED_FIXTURE_PATHS`; `scripts/validate-test-layout.ts` emits the FR-9 output format and exits non-zero on violations; `npm run validate` chains layout validator before build validator; `.husky/pre-commit` invokes `npm run validate` after `npm audit`; misplacement smoke test confirms the validator fires correctly.
- Phase 5: `scripts/hooks/validate-test-layout-hook.ts` reads stdin and rejects misplaced paths with rule-named messages; `.claude/settings.json` wires the hook with `Write|Edit` matcher; bats suite covers all paths including Edge Case 4 fail-open; both validator and hook import from `scripts/test-layout-rules.ts` (Edge Case 5).
- Phase 6: CLAUDE.md and every `SKILL.md` reference the new layout; `executing-qa/SKILL.md` line ~178 rewritten; `/plugin install` verification returns empty `find` (FR-12); NFR-1 zero-loss and NFR-4 runtime targets met and documented in PR body.
- Overall: Issue [#255](https://github.com/lwndev/lwndev-marketplace/issues/255) closes on merge via `Closes #255` in the PR body; PR contains one commit per phase boundary (NFR-6); plugin-install payload drops by ~68 `.bats` files plus the 51 `.test.ts`/`.spec.ts` files (NFR-5).
