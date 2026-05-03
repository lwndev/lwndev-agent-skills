# Feature Requirements: Consolidate test layout under tests/ with enforcement

## Overview

Consolidate every test file in the repository under a single `tests/` root with two leaves chosen by runner (`tests/unit/` for Vitest TS tests, `tests/bats/` for Bats shell tests), unify `npm test` to run both runners, and add validator + hook enforcement so misplaced tests cannot regress the layout. Resolves the test-location drift that ships Bats files into user `/plugin install` payloads, leaves `.spec.ts` files inconsistently named (mixed casing — `qa-FEAT-020.spec.ts` vs `qa-feat-024-rollout.test.ts`), and forces contributors to invoke two runners separately.

The `requirements/implementation/FEAT-031-inventory.md` artifact is preserved research input from closed issue [#235](https://github.com/lwndev/marketplace/issues/235); it is reusable fact-finding (file lists, convention picks, fixture decisions) but is not authored as part of this feature. The new feature requirements doc below is the authoritative scope.

## Feature ID

`FEAT-031`

## GitHub Issue

[#255](https://github.com/lwndev/lwndev-marketplace/issues/255)

## Priority

Medium — the current layout is functional but causes ongoing friction (test-shipping, conflicting authoring guidance, no CI for Bats). Not blocking active feature work, but every new test added under the current layout deepens the drift this feature corrects.

## User Story

As a contributor to lwndev-marketplace, I want a single tests root with one runner per language (Vitest for TS, Bats for shell) and a unified `npm test` command, so that I can find tests predictably, run them all in one command, and not accidentally ship test files to plugin users.

As a `/plugin install` user of lwndev-sdlc, I want the installed plugin to contain only the runtime files I will execute, so that my Claude config stays small and free of contributor-only artifacts.

## Functional Requirements

### FR-1: Single tests/ root with runner-scoped leaves

Final on-disk layout:

```
tests/
├── unit/                 # Vitest, .test.ts only
│   └── *.test.ts
├── bats/                 # Bats, .bats only
│   ├── shared/
│   │   └── hooks/
│   └── skills/
│       └── <skill>/
└── fixtures/             # Shared test fixtures (TS-side)
    └── qa-fixture/
```

- Exact subdirectory names under `tests/bats/` mirror the source tree they replace: `shared/` ← `plugins/lwndev-sdlc/scripts/tests/`, `shared/hooks/` ← `plugins/lwndev-sdlc/scripts/tests/hooks/`, `skills/<skill>/` ← `plugins/lwndev-sdlc/skills/<skill>/scripts/tests/`.
- No tests of any kind exist under `plugins/` after this feature lands.

### FR-2: Vitest TS tests relocated and normalized

- Move all 42 `.test.ts` files from `scripts/__tests__/` to `tests/unit/`.
- Rename all 8 non-fixture `.spec.ts` files to `.test.ts` and apply kebab-case (per FEAT-031 inventory's rename table). All 8 are currently passing — rename is mechanical, no production-code edits. Seven of the eight live under `scripts/__tests__/`; the eighth lives at the repo root as `__tests__/qa-feat-030-contract.spec.ts` and must move into `tests/unit/` along with the others. The now-empty root `__tests__/` directory is removed once the file is moved.
- Relocate `scripts/__tests__/fixtures/qa-fixture/` to `tests/fixtures/qa-fixture/` and update any harness path references.
- Stay-in-place exceptions: `scripts/__tests__/fixtures/feat-030-known-buggy/` (and its `__tests__/qa-buggy.spec.ts`, which is allow-ruled in the validator) remains where it is — the `feat-030-executing-qa.test.ts` harness invokes the fixture's own `vitest.config.ts` as a child process; moving it would break the harness. `scripts/__tests__/fixtures/qa-fixture-empty/` also stays in place per the FEAT-031 inventory decision (README-only directory referenced by `qa-integration.test.ts`); moving it would force a harness path update for no migration benefit.
- Final on-disk extension: `.test.ts` only (the `feat-030-known-buggy` fixture `.spec.ts` is the documented exception).

### FR-3: Bats tests relocated out of `plugins/`

- Move all 68 `.bats` files from `plugins/lwndev-sdlc/{scripts,skills/<skill>/scripts}/tests/` to `tests/bats/{shared,skills/<skill>}/`.
- Rewrite the path resolution inside each `.bats` file. The current files do **not** use `load` directives — they resolve helper script paths via `BATS_TEST_DIRNAME` (e.g., `SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"` to reach the runtime script under test). The relocation changes the relative depth from each test file to its target script, so every `BATS_TEST_DIRNAME`-anchored path expression in the `.bats` files (including any `setup()`-block path setup) must be rewritten to span the new gap from `tests/bats/<leaf>/` to `plugins/lwndev-sdlc/<scripts|skills/<skill>/scripts>/`. The replacement formula differs by leaf because skill leaves carry one extra path segment (`<skill>/`):

  | Old leaf | New leaf | Replacement |
  |----------|----------|-------------|
  | `plugins/lwndev-sdlc/scripts/tests/` | `tests/bats/shared/` | `${BATS_TEST_DIRNAME}/..` → `${BATS_TEST_DIRNAME}/../../../plugins/lwndev-sdlc/scripts` |
  | `plugins/lwndev-sdlc/skills/<skill>/scripts/tests/` | `tests/bats/skills/<skill>/` | `${BATS_TEST_DIRNAME}/..` → `${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/<skill>/scripts` |

  Implementation: two scoped sed passes (one per leaf) keyed off the original location, not a single global pass — the per-skill segment in the skill-leaf replacement is a literal substitution that only applies to files moving from `skills/<skill>/scripts/tests/`.
- Helper scripts stay where they are (they are runtime scripts under `plugins/lwndev-sdlc/{scripts,skills/<skill>/scripts}/`); only the test files move.
- Delete now-empty `plugins/lwndev-sdlc/scripts/tests/` and per-skill `plugins/lwndev-sdlc/skills/<skill>/scripts/tests/` directories after the move.

### FR-4: Vitest configuration updated

- `vitest.config.ts` `testMatch` becomes `['tests/unit/**/*.test.ts']`.
- `coverage.include` and `coverage.exclude` updated to reflect the new layout (include: `scripts/**/*.ts`; exclude: `tests/**`, `**/*.test.ts`, fixture trees).
- Existing fixture exclusion for `scripts/__tests__/fixtures/feat-030-known-buggy/` is preserved (its harness still drives a child Vitest invocation against the fixture's own config).

### FR-5: TypeScript test config

- New file `tsconfig.test.json` extending `tsconfig.json` with `include: ["tests/**/*.ts"]`.
- Root `tsconfig.json` keeps `rootDir: "./scripts"` and `include: ["scripts/**/*.ts"]` unchanged so non-test compilation is untouched.

### FR-6: ESLint integration

- `eslint.config.js` `parserOptions.project` becomes `['./tsconfig.json', './tsconfig.test.json']`.
- `lint` and `format` globs in `package.json` widen to `scripts/ tests/`.
- `lint-staged` glob widens to include `tests/**/*.ts`.

### FR-7: Bats runner installation

Install Bats as an npm devDependency (option (a) from the issue). Rationale: the npm package wraps bats-core, declares the dependency in `package.json` so contributors get `bats` automatically with `npm install`, and surfaces the version pin in lockfile review. Options (b) Homebrew via README and (c) detect-and-install both push the install burden onto contributors or `npm test` runtime.

- `npm install --save-dev bats` adds the dependency. Pin to `^1.10.0` (semver caret) — the npm `bats` package wraps the bats-core project and its 1.x line is the maintained distribution channel. The implementation step verifies the latest 1.x at install time and bumps the caret floor only if necessary.
- `npx bats <path>` becomes the canonical invocation.
- Document the contributor command in `CLAUDE.md` (or `README.md` if a contributors section is added).

### FR-8: Unified `npm test`

- `package.json` adds `test:unit` (`vitest run`) and `test:bats` (`npx bats tests/bats`) scripts.
- `test` becomes `npm run test:unit && npm run test:bats`.
- `test` exits non-zero if either runner fails. Bats exit code propagates through the `&&` chain naturally.

### FR-9: Layout validator script

- New `scripts/validate-test-layout.ts` enforces (using the shared allow-rule constant from Edge Case 5). Each rule has a normative ID that the validator and hook (FR-10) both emit, sourced from a shared `scripts/test-layout-rules.ts` module so the two tools cannot diverge on naming:
  1. `ts-outside-tests-unit` — no `*.test.ts` exists outside `tests/unit/`.
  2. `spec-extension-disallowed` — no `*.spec.ts` exists anywhere (the `feat-030-known-buggy/__tests__/qa-buggy.spec.ts` fixture is the only allow-ruled exception).
  3. `bats-outside-tests-bats` — no `*.bats` exists outside `tests/bats/`.
- Validator is wired into `npm run validate` by chaining ahead of the existing manifest validator: `package.json`'s `validate` script becomes `tsx scripts/validate-test-layout.ts && tsx scripts/build.ts`. `build.ts` is not modified — the layout validator runs as a separate process so a layout failure short-circuits the chain before plugin-manifest validation.
- Validator is wired into `.husky/pre-commit` (appended after the existing chain, per FEAT-031 inventory rationale: `lint-staged` scopes to staged files only; the validator must scan the whole tree).
- Validator emits one line per violation with the full path and the rule that fired; exits non-zero on any violation.

### FR-10: PreToolUse enforcement hook

- `.claude/settings.json` (project-scoped, checked in) adds a `PreToolUse` hook matching `Write|Edit` that blocks writes to misplaced test paths so test-generating skills cannot regress the layout.
- Hook receives the standard `tool_input.file_path` payload on stdin and rejects when `file_path` matches the same rules as the validator (using the shared allow-rule constant from Edge Case 5):
  - `*.test.ts` outside `tests/unit/`
  - any `*.spec.ts` (fixture excepted)
  - any `*.bats` outside `tests/bats/`
- Rejection message names the rule that fired and the canonical destination so the model can self-correct.
- Hook is implemented as a small script under `scripts/hooks/` (creating the directory). The plugin-internal `plugins/lwndev-sdlc/scripts/hooks/` path is rejected: those hooks ship to user `/plugin install` payloads via the marketplace, contradicting FR-10's project-scoped framing and partially undermining FR-12.

### FR-11: Documentation alignment

- Update `CLAUDE.md` "Skill Authoring" §3 ("Every script behavior needs bats coverage") to state: TS modules → Vitest under `tests/unit/`; shell scripts → Bats under `tests/bats/{shared,skills/<skill>}/`.
- Update `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` line ~178 (the `vitest / jest: __tests__/qa-<dimension>.spec.ts (or .test.ts per project config)` bullet inside Step 4 "Test-framework mode -- write and run") to reference `tests/unit/qa-<dimension>.test.ts` and drop the parenthetical extension confusion. The textual quote anchors the location.
- Audit every other `SKILL.md` for `__tests__/` or `.spec.ts` mentions and align with the new layout.

### FR-12: Plugin install payload verification

- After the relocation, `/plugin install lwndev-sdlc` against a fresh config copies zero `.bats` or `.test.ts` / `.spec.ts` files into the user's plugin directory (default `~/.claude/plugins/lwndev-sdlc/`, or `$CLAUDE_CONFIG_DIR/plugins/lwndev-sdlc/` when the user has overridden the default config path).
- Acceptance verified by a manual install + `find <plugin-install-path> -type f \( -name '*.bats' -o -name '*.test.ts' -o -name '*.spec.ts' \)` returning empty.

## Output Format

Not applicable — this feature has no user-facing CLI surface. Validator output (FR-9) is the only structured output:

```
[validate-test-layout] FAIL: scripts/__tests__/foo.test.ts -> rule=ts-outside-tests-unit
[validate-test-layout] FAIL: scripts/__tests__/baz.spec.ts -> rule=spec-extension-disallowed
[validate-test-layout] FAIL: plugins/lwndev-sdlc/scripts/tests/bar.bats -> rule=bats-outside-tests-bats
3 violations
```

Exit code 1 on any violation; exit code 0 on a clean tree.

## Non-Functional Requirements

### NFR-1: Zero-loss migration

- Every test that runs and passes before the feature continues to run and pass after. No tests are silently dropped, skipped, or excluded.
- Validated by capturing the pre-feature `npm test` test count + pass/fail summary on `main`, then comparing against the post-feature count + summary on the feature branch.

### NFR-2: Test invocation contracts preserved

- `npm test`, `npm run test:watch`, `npm run test:coverage` continue to work. Watch and coverage modes wrap Vitest only (Bats has no equivalent watch mode, and adding one is out of scope).
- `npm run test-skill` (single-skill driver) continues to work; it does not run `.bats` and is unaffected.

### NFR-3: Pre-commit and CI consistency

- Pre-commit hook (`.husky/pre-commit`) continues to run the existing chain plus the new validator. Hook order: `lint-staged → lint → format:check → test → audit → validate`.
- The existing `.github/workflows/ci.yml` job (steps: `npm run lint`, `npm run format:check`, `npm test`, `npm audit`, `npm run validate`) inherits the unified Vitest+Bats run automatically through its `npm test` step once `package.json`'s `test` script is rewired (FR-8). No CI workflow edits required for the `npm test` change itself; if Bats output is desired as a separate CI step for reporting clarity, the implementation may optionally add a `npm run test:bats` step (out of scope unless the contributor running the implementation chooses to include it).

### NFR-4: Performance

- `npm test` runtime increases by Bats execution time only (currently ~no time — Bats was never run via `npm test`). Target: total runtime under 2× the pre-feature Vitest-only runtime. If exceeded, investigate parallelism or test pruning before merging.

### NFR-5: Plugin payload reduction

- Installed plugin payload (`du -sh ~/.claude/plugins/lwndev-sdlc/`) drops by the size of the relocated `.bats` files (currently ~68 files).

### NFR-6: Reversibility

- The relocation is captured as a single PR with one commit-per-phase (or per-logical-step) so it is reviewable and revertible. Phase boundaries are: Vitest relocation; Bats relocation; config + npm-script updates; validator; hook; doc alignment.

## API Integration

Not applicable.

## Dependencies

- `bats` (npm package, new devDependency). Version: latest stable at implementation time, pinned in `package.json` and `package-lock.json`.
- No production dependencies added.
- Existing dependencies (Vitest, ESLint, Husky, lint-staged, Prettier) remain at current versions.

## Edge Cases

1. **`feat-030-known-buggy` fixture**: Stay-in-place with the existing exclude rule. The harness `feat-030-executing-qa.test.ts` invokes a child Vitest pointed at the fixture's own `vitest.config.ts`. Moving it would break relative paths inside the harness. Validator must allow this single `.spec.ts` path.

2. **Bats path-resolution rewrites**: Each `.bats` file's `BATS_TEST_DIRNAME`-anchored path expression (e.g. `SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"`) encodes the relative depth from the test file to the runtime helper script under `plugins/lwndev-sdlc/...`. Moving the test file changes that depth, so every `BATS_TEST_DIRNAME`-anchored expression must be rewritten per the FR-3 replacement table. The existing `.bats` files do not use `load` directives — verified across all 68 files. Verify by running `npx bats tests/bats` after the move; broken paths fail fast at test discovery time.

3. **`qa-fixture` harness reference**: The `qa-fixture/` directory is referenced by `scripts/__tests__/qa-integration.test.ts`, `scripts/__tests__/qa-dependency-failure-BUG-012.test.ts`, and `scripts/__tests__/qa-inputs-BUG-012.test.ts`. Any harness reference to `scripts/__tests__/fixtures/qa-fixture/` must update to `tests/fixtures/qa-fixture/`.

4. **PreToolUse hook applies to all `Write`/`Edit`**: The hook fires on every `Write`/`Edit` regardless of file content. The path-based filter must short-circuit on non-test paths (i.e., paths that don't match `*.test.ts`, `*.spec.ts`, or `*.bats`) so the hook is essentially a no-op for non-test edits. Fail open on parse error so the hook never blocks legitimate work.

5. **Validator vs. fixture allow-rule (shared constant)**: The validator (FR-9) and the hook (FR-10) share an allow-rule for `feat-030-known-buggy/__tests__/qa-buggy.spec.ts`. Either both honor the allow-rule or neither does — split state would let one tool block work that the other tool generates. Codify the allow-rule as a constant shared between validator and hook implementations (e.g., `scripts/test-layout-rules.ts` exporting `ALLOWED_FIXTURE_PATHS` consumed by `validate-test-layout.ts` and the hook script). Both FR-9 and FR-10 reference this shared constant explicitly.

6. **Re-classification on resume**: If implementation pauses and resumes, the post-relocation working tree state is the source of truth. The validator can be run any time as a smoke test.

7. **Marketplace install path**: `.claude-plugin/marketplace.json` `source` already points to `./plugins/lwndev-sdlc`. After the relocation, plugins/ has no test files, so the install payload naturally excludes them. No `.claude-plugin/marketplace.json` change required (verified via FR-12).

8. **Empty parent directories**: After moving the per-skill `tests/` directories out, the now-empty `plugins/lwndev-sdlc/skills/<skill>/scripts/tests/` directories must be deleted (git tracks file presence, not directory presence — but leaving them makes the layout confusing).

## Testing Requirements

### Unit Tests

- `scripts/validate-test-layout.ts` has a Vitest test suite under `tests/unit/validate-test-layout.test.ts` covering: no violations on clean tree; correct violation when `.test.ts` lives outside `tests/unit/`; correct violation when `.spec.ts` exists; correct violation when `.bats` lives outside `tests/bats/`; allow-rule passes for the `feat-030-known-buggy` fixture; exit code 0 on clean / 1 on violations.
- Hook script has a Bats test suite under `tests/bats/shared/hooks/validate-test-layout-hook.bats` covering: rejects misplaced `*.test.ts`; rejects `*.spec.ts`; rejects misplaced `*.bats`; allow-rule passes for the fixture; allows non-test edits; **fails open on malformed `tool_input` JSON** (Edge Case 4).

### Integration Tests

- A repo-level smoke test (manual or scripted): run `npm test` on a fresh checkout, verify both runners execute and exit 0.
- Run `npm run validate` and confirm the layout validator passes on the post-feature tree.
- Trigger the PreToolUse hook against synthetic `tool_input.file_path` values and confirm reject vs. allow decisions.

### Manual Testing

- `/plugin install lwndev-sdlc` against a fresh Claude config; `find ~/.claude/plugins/lwndev-sdlc -type f \( -name '*.bats' -o -name '*.test.ts' -o -name '*.spec.ts' \)` returns empty (FR-12).
- Compare pre- and post-feature test counts: `npm test 2>&1 | tee /tmp/pre-test.log` on `main`, then on the feature branch, diff totals.

## Future Enhancements

- Optionally split Bats into its own CI step for reporting clarity (currently `.github/workflows/ci.yml` runs `npm test` which will invoke both runners after FR-8; a separate `npm run test:bats` step gives Bats failures a dedicated GitHub Actions job-step bubble).
- Add coverage thresholds (out of scope; tracked separately).
- Migrate shell scripts to a different language (out of scope; would change this analysis).
- Add new tests for currently-uncovered behavior (out of scope; tracked separately).

## Acceptance Criteria

- [x] No `*.test.ts`, `*.spec.ts`, or `*.bats` file exists under `plugins/`.
- [x] All `plugins/lwndev-sdlc/scripts/tests/` and `plugins/lwndev-sdlc/skills/<skill>/scripts/tests/` directories are removed post-move (FR-3, Edge Case 8).
- [x] `tests/unit/` is the single Vitest root; `tests/bats/` is the single Bats root.
- [x] `tests/unit/` contains only `.test.ts` files (with the documented `feat-030-known-buggy` fixture exception staying outside `tests/unit/`).
- [x] All file names in `tests/unit/` use kebab-case.
- [x] `npm test` runs both Vitest and Bats and exits non-zero if either runner fails.
- [x] `npm run test:unit` runs Vitest only; `npm run test:bats` runs Bats only.
- [x] `npm run test:watch`, `npm run test:coverage`, and `npm run test-skill` continue to function on the post-feature tree (NFR-2).
- [x] `package.json` lists `bats` as a devDependency pinned to `^1.10.0` (or higher 1.x caret).
- [x] `package.json` `lint`, `format`, and `lint-staged` globs include `tests/**` (FR-6).
- [x] `vitest.config.ts` `testMatch` is `['tests/unit/**/*.test.ts']`; `coverage.include` and `coverage.exclude` reflect the new layout (FR-4).
- [x] `tsconfig.test.json` exists and extends `tsconfig.json`.
- [x] `eslint.config.js` references both tsconfigs.
- [x] `npm run validate` fails on misplaced test files (validated by an artificial misplacement during implementation, then reverted).
- [x] `.husky/pre-commit` invokes `npm run validate` after `npm audit` (FR-9, NFR-3).
- [x] `.github/workflows/ci.yml` continues to pass on the feature branch — no workflow edits required, the existing `npm test` step picks up Bats automatically (NFR-3).
- [x] PreToolUse hook in `.claude/settings.json` blocks `Write`/`Edit` to disallowed paths and fails open on malformed `tool_input` JSON (FR-10, Edge Case 4).
- [x] `CLAUDE.md` and every `SKILL.md` that mentions test placement reference the new layout.
- [x] `/plugin install lwndev-sdlc` against a fresh config copies zero test files into the user's plugin directory.
- [x] Pre- and post-feature Vitest test counts match (NFR-1). The post-feature Bats count is recorded separately for reference but is not subject to the no-loss check (Bats was never invoked via `npm test` pre-feature).
- [x] Post-feature `npm test` runtime is within 2× the pre-feature Vitest-only runtime (NFR-4); document the measured before/after numbers in the PR description.
- [x] PR contains one commit per logical phase boundary (Vitest relocation; Bats relocation; config + npm-script updates; validator; hook; doc alignment) so the relocation is reviewable and revertible (NFR-6).
- [x] `CLAUDE.md` (or `README.md` if a contributors section is added) documents the contributor `npx bats <path>` invocation per FR-7.
- [x] Bats runner is installable via `npm install` with no separate contributor instructions required.

## Completion

**Status:** `Complete`

**Completed:** 2026-05-03

**Pull Request:** [#256](https://github.com/lwndev/lwndev-marketplace/pull/256)
