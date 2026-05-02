# FEAT-031 Phase 1 Inventory

Canonical reference for all per-file and per-decision data. Every subsequent phase references this document.

---

## FR-1: Working-tree scan

### `.test.ts` files (42 files — under `scripts/__tests__/`)

All 42 are currently picked up by `npm test` via `testMatch: ['**/__tests__/**/*.test.ts']`.

```
scripts/__tests__/argument-hint.test.ts
scripts/__tests__/build.test.ts
scripts/__tests__/capability-discovery.test.ts
scripts/__tests__/constants.test.ts
scripts/__tests__/creating-implementation-plans.test.ts
scripts/__tests__/documenting-bugs.test.ts
scripts/__tests__/documenting-chores.test.ts
scripts/__tests__/documenting-features.test.ts
scripts/__tests__/documenting-qa.test.ts
scripts/__tests__/executing-bug-fixes.test.ts
scripts/__tests__/executing-chores.test.ts
scripts/__tests__/executing-qa.test.ts
scripts/__tests__/feat-030-executing-qa.test.ts
scripts/__tests__/finalizing-workflow.test.ts
scripts/__tests__/git-utils.test.ts
scripts/__tests__/implementing-plan-phases.test.ts
scripts/__tests__/managing-work-items.test.ts
scripts/__tests__/orchestrating-workflows.test.ts
scripts/__tests__/persona-loader.test.ts
scripts/__tests__/prompts.test.ts
scripts/__tests__/qa-bug-013.test.ts
scripts/__tests__/qa-BUG-014.test.ts
scripts/__tests__/qa-bug-015-gates.test.ts
scripts/__tests__/qa-CHORE-036.test.ts
scripts/__tests__/qa-dependency-failure-BUG-012.test.ts
scripts/__tests__/qa-feat-023-rollout.test.ts
scripts/__tests__/qa-feat-024-rollout.test.ts
scripts/__tests__/qa-feat-027.test.ts
scripts/__tests__/qa-feat-028.test.ts
scripts/__tests__/qa-inputs-BUG-012.test.ts
scripts/__tests__/qa-integration.test.ts
scripts/__tests__/qa-managing-work-items.test.ts
scripts/__tests__/qa-reviewing-requirements.test.ts
scripts/__tests__/qa-verifier.test.ts
scripts/__tests__/release-tag.test.ts
scripts/__tests__/release.test.ts
scripts/__tests__/reviewing-requirements.test.ts
scripts/__tests__/scaffold.test.ts
scripts/__tests__/shared-scripts.test.ts
scripts/__tests__/skill-utils.test.ts
scripts/__tests__/test-skill.test.ts
scripts/__tests__/workflow-state.test.ts
```

Phase 1 adds 2 more under `tests/unit/`:
```
tests/unit/scripts/_helpers/run-script.test.ts   (new — FR-4 helper)
tests/unit/scripts/shared/slugify.test.ts         (new — FR-3 spike)
```

### `.spec.ts` files (8 files — pre-existing + 1 fixture)

**Important correction to plan description**: The plan stated these were "silently never run." In Vitest v3, the `testMatch: ['**/__tests__/**/*.test.ts']` pattern also matches `.spec.ts` files (Vitest v3 glob matching includes `.spec.ts` variants). All 8 spec files below are currently running and **passing**. The fixture entry is excluded via the explicit `exclude` rule.

| File | Currently runs | Tests passing | Fix-or-delete decision |
|------|---------------|---------------|------------------------|
| `scripts/__tests__/qa-CHORE-034.spec.ts` | YES (29 tests pass) | Yes | **Fix**: rename to `qa-CHORE-034.test.ts`, move to `tests/unit/` in Phase 2 |
| `scripts/__tests__/qa-CHORE-035.spec.ts` | YES (47 tests pass) | Yes | **Fix**: rename to `qa-CHORE-035.test.ts`, move to `tests/unit/` in Phase 2 |
| `scripts/__tests__/qa-FEAT-020.spec.ts` | YES (21 tests pass) | Yes | **Fix**: rename to `qa-feat-020.test.ts` (kebab-case per FR-2), move to `tests/unit/` in Phase 2 |
| `scripts/__tests__/qa-FEAT-021.spec.ts` | YES (39 tests pass) | Yes | **Fix**: rename to `qa-feat-021.test.ts` (kebab-case per FR-2), move to `tests/unit/` in Phase 2 |
| `scripts/__tests__/qa-FEAT-022.spec.ts` | YES (16 tests pass) | Yes | **Fix**: rename to `qa-feat-022.test.ts` (kebab-case per FR-2), move to `tests/unit/` in Phase 2 |
| `scripts/__tests__/qa-feat-029.spec.ts` | YES (5 tests pass) | Yes | **Fix**: rename to `qa-feat-029.test.ts`, move to `tests/unit/` in Phase 2 |
| `scripts/__tests__/qa-finalizing-workflow-inputs.spec.ts` | YES (14 tests pass) | Yes | **Fix**: rename to `qa-finalizing-workflow-inputs.test.ts`, move to `tests/unit/` in Phase 2 |
| `__tests__/qa-feat-030-contract.spec.ts` | YES (7 tests pass) | Yes | **Fix**: rename to `qa-feat-030-contract.test.ts`, move to `tests/unit/` in Phase 2 |
| `scripts/__tests__/fixtures/feat-030-known-buggy/__tests__/qa-buggy.spec.ts` | NO (excluded) | N/A — intentionally failing fixture | **Stay-in-place allow-rule**: kept as `.spec.ts`, excluded from top-level testMatch, invoked only by `feat-030-executing-qa.test.ts` as child process |

All fix decisions involve rename + move with no production-code changes needed — tests are currently passing.

### `.bats` files (68 files)

#### Top-level shared (14 files under `plugins/lwndev-sdlc/scripts/tests/`)
```
branch-id-parse.bats
build-branch-name.bats
check-acceptance.bats
checkbox-flip-all.bats
commit-work.bats
create-pr.bats
ensure-branch.bats
new-requirement.bats
next-id.bats
prepare-fork.bats
resolve-requirement-doc.bats
slugify.bats         ← FR-3 spike (Phase 1)
validate-categories.bats
verify-build-health.bats
```

#### Hooks (6 files under `plugins/lwndev-sdlc/scripts/tests/hooks/`)
```
auto-mode-end-to-end.bats
guard-agent-prompts.bats
guard-findings-edits.bats
guard-state-transitions.bats
record-approval.bats
workflow-state-pausedat.bats
```

#### Skill-level tests (48 files)
```
creating-implementation-plans/ (6): phase-complexity-budget, qa-feat-029-gaps, render-plan-scaffold, split-phase-suggest, validate-phase-sizes, validate-plan-dag
documenting-bugs/ (1): validate-rc-traceability
executing-qa/ (9): capability-report-diff, check-branch-diff, commit-qa-tests, qa-baseline, qa-reconcile-delta, qa-verify-coverage, render-qa-results, run-framework, stop-hook
finalizing-workflow/ (6): check-idempotent, completion-upsert, finalize, finalize.e2e, preflight-checks, reconcile-affected-files
implementing-plan-phases/ (6): check-deliverable, commit-and-push-phase, next-pending-phase, plan-status-marker, verify-all-phases-complete, verify-phase-deliverables
managing-work-items/ (6): backend-detect, extract-issue-ref, fetch-issue, post-issue-comment, pr-link, render-issue-comment
orchestrating-workflows/ (8): check-resume-preconditions, findings-decision, init-workflow, parse-findings, parse-model-flags, parse-qa-return, resolve-pr-number, workflow-state-record-findings-qa
reviewing-requirements/ (6): cross-ref-check, detect-review-mode, extract-references, pr-diff-vs-plan, reconcile-test-plan, verify-references
```

**Note**: Plan mentioned "50 / 20 / 48" in the issue figures. Actual count is 42 `.test.ts` + 8 `.spec.ts` = 50 total existing, and 68 `.bats` files (not 48 — the plan's "48" may have been an earlier revision count; actual bats total is 68 = 14 top-level + 6 hooks + 48 skill-level).

---

## FR-2: Convention decisions (binding)

| Convention | Decision |
|-----------|---------|
| Extension | `.test.ts` only — no `.spec.ts` (except the fixture allow-rule) |
| Casing | `kebab-case` — file names use lowercase-hyphen (e.g. `slugify.test.ts`, not `Slugify.test.ts`) |
| QA naming | `qa-<dimension>.test.ts` — per-adversarial-dimension naming (e.g. `qa-inputs.test.ts`, `qa-error-handling.test.ts`). Rationale: `executing-qa/SKILL.md:178` already emits dimension-keyed paths; FR-12 rewrites that contract to `tests/unit/qa-<dimension>.test.ts` |

---

## FR-1 (cont.): Fixture subtree decisions

| Subtree | Decision | Rationale |
|---------|---------|---------|
| `scripts/__tests__/fixtures/feat-014/` | **Stay-in-place** (no allow-rule needed — contains no `.test.ts`/`.spec.ts`, only markdown data) | No test files; the parent `testMatch` does not reach inside it |
| `scripts/__tests__/fixtures/feat-030-known-buggy/` | **Stay-in-place** with allow-rule for `__tests__/qa-buggy.spec.ts` | Intentional harness fixture; `feat-030-executing-qa.test.ts` invokes child Vitest pointed at the fixture's own `vitest.config.ts`. Must not move or the relative paths inside the harness break |
| `scripts/__tests__/fixtures/feat-030-known-buggy/vitest.config.ts` | **Stay-in-place** | Child target config; moving it would break the harness invocation in `feat-030-executing-qa.test.ts` |
| `scripts/__tests__/fixtures/qa-fixture/` | **Relocate** to `tests/fixtures/qa-fixture/` in Phase 2 | Contains vitest config + test files; falls under the migration. The `qa-fixture/vitest.config.ts` is reconciled per FR-9 decision below |
| `scripts/__tests__/fixtures/qa-fixture-empty/` | **Stay-in-place** | README-only; no test files |

---

## FR-9 decisions (tsconfig + qa-fixture)

**tsconfig choice**: Introduce `tsconfig.test.json` extending `tsconfig.json` with `include: ["tests/**/*.ts"]`. The root `tsconfig.json` keeps `rootDir: "./scripts"` and `include: ["scripts/**/*.ts"]` unchanged. This resolves I3 (scripts rootDir incompatibility with tests tree). ESLint `parserOptions.project` becomes `['./tsconfig.json', './tsconfig.test.json']`.

**vitest.config.ts testMatch — Phase 1 choice (FR-9)**: Phase 1 widens `testMatch` to `['**/__tests__/**/*.test.ts', '**/tests/unit/**/*.test.ts']` so the new helper and spike are picked up alongside existing tests. Phase 2 narrows to `['tests/unit/**/*.test.ts']` exclusively after all existing tests are migrated. This dual-include approach avoids any enforcement collision during the migration window.

**qa-fixture reconciliation**: Relocate `scripts/__tests__/fixtures/qa-fixture/` → `tests/fixtures/qa-fixture/` in Phase 2. Update any harness paths that reference it. Remove from the top-level `vitest.config.ts` exclude if present (the new path falls outside `tests/unit/**` so testMatch already won't match it).

**bats case replacement literal**: The `qa-verify-coverage.bats` references `expected: bats case` (the mode label used in QA test plans). The replacement literal is `vitest case`. Apply uniformly in Phase 18 across `executing-qa` templates, persona prompts, JSON schemas, and any `documenting-qa` references.

---

## FR-14: Husky wiring decision

**Choice**: Append `npm run validate` to `.husky/pre-commit` after the existing chain. The final hook reads:
```
npx lint-staged
npm run lint
npm run format:check
npm test
npm audit --audit-level=high
npm run validate
```

Rationale: routing through `lint-staged` only runs on staged files; the layout validator must scan the whole tree to detect misplaced test files anywhere.

---

## FR-15: PreToolUse JSON shape reference

Captured from `.claude/settings.local.json` (the project's current settings). The Claude Code `PreToolUse` hook shape:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "<shell command to evaluate; receives JSON on stdin>"
          }
        ]
      }
    ]
  }
}
```

The hook receives a JSON payload on stdin. Relevant fields:
- `tool_name`: the tool being invoked (e.g., `"Write"`, `"Edit"`)
- `tool_input.file_path`: the target file path for `Write`/`Edit`/`MultiEdit`

To deny, the command must exit non-zero and write a reason to stdout (the reason is shown to the model as the rejection message). To allow, exit 0.

The checked-in file is `.claude/settings.json` (not `settings.local.json` which is gitignored). FR-15 creates `.claude/settings.json` in Phase 19.

**Note**: The existing `settings.local.json` shows a `SubagentStart` hook example that confirms the hook command receives a JSON payload piped via stdin (`cat | jq -r ...`).

---

## FR-3: Slugify baselines

**Method**: Each timed 3 times; median recorded.

| Runner | Run 1 | Run 2 | Run 3 | Median |
|--------|-------|-------|-------|--------|
| bats (slugify.bats, 12 tests) | 0.490s | 0.489s | 0.466s | **0.489s** |
| Vitest (slugify.test.ts, 12 tests) | 0.510s | 0.454s | 0.447s | **0.454s** |

**Ratio**: 0.454 / 0.489 = **0.93x** (Vitest is faster than Bats for this 12-test suite).
**Delta**: -0.035s (Vitest is 35 ms faster).

Threshold check: `ratio >= 2x AND delta >= 2s` → **NOT breached**. Proceeding with Phase 2+.

---

## NFR-1: npm test wall-clock baseline

**Machine**: MacBook (darwin 25.4.0, Apple Silicon implied).
**Method**: `time npm test` run 3 times on an idle machine; median recorded.

| Run | Duration (Vitest "Duration" field) | Wall-clock |
|-----|--------|--------|
| 1 | 53.60s | 53.89s |
| 2 | 52.67s | 52.93s |
| 3 | 52.67s | 52.93s |

**NFR-1 baseline median**: **52.93s** (wall-clock).

Budget anchor: Phase 17 end-state suite must complete in ≤ **105.86s** (2x baseline). Each port phase should add at most ~1-2 s of overhead per 5-file batch of Vitest script spawns.

---

## FR-4 spawn helper

**Location**: `tests/unit/scripts/_helpers/run-script.ts`

Named exports:
- `runScript(scriptPath, args?, opts?) -> {stdout, stderr, status, signal}` — uses `child_process.spawnSync` with `bash` as the interpreter
- `tempDir(prefix?) -> {path, cleanup()}` — creates a temp dir with cleanup
- `gitFixture(opts?) -> {path, cleanup(), commit(files, msg?)}` — creates a git repo with an initial commit

No `execa` import. No default export. Uses `child_process.spawnSync` (Node stdlib).

**execa confirmation**: grep across `scripts/` and `package.json` confirms no `execa` import exists anywhere in the repo.

---

## Per-assertion inventory (Bats files)

### Top-level shared scripts (`plugins/lwndev-sdlc/scripts/tests/`)

#### `branch-id-parse.bats` (16 assertions)
1. happy path: feat/FEAT-001-scaffold-skill
2. happy path: chore/CHORE-023-cleanup
3. happy path: fix/BUG-011-null-crash
4. main branch: exit 1 with pattern error
5. happy path: release/lwndev-sdlc-v1.16.0
6. happy path: release/foo-bar-v0.1.2
7. happy path: release/x-v10.20.30
8. malformed release: release/foo (no version) exit 1
9. malformed release: release/foo-v1.2 (incomplete version) exit 1
10. malformed release: release/foo/bar-v1.0.0 (nested path) exit 1
11. non-canonical prefix bug/: exit 1
12. missing slash after FEAT-NNN: exit 1 (trailing '-' required)
13. missing arg: exit 2
14. jq-absent fallback: valid JSON still emitted
15. jq-absent fallback: release case emits literal null for id/dir
16. feat/FEAT-001- without trailing content still matches

#### `build-branch-name.bats` (11 assertions)
1. happy path: feat FEAT-001 'scaffold skill' → feat/FEAT-001-scaffold-skill
2. stopword summary: feat FEAT-001 'The Art of War' → feat/FEAT-001-art-war
3. chore type: chore CHORE-023 'cleanup deps' → chore/CHORE-023-cleanup-deps
4. fix type: fix BUG-011 'null crash' → fix/BUG-011-null-crash
5. invalid type 'foobar': exit 2
6. invalid type 'feature' (long form rejected): exit 2
7. empty summary (all stopwords): exit 1 propagated from slugify
8. punctuation-only summary: exit 1 propagated from slugify
9. missing args (zero): exit 2
10. missing args (two): exit 2
11. slugify is called via the sibling script regardless of CWD

#### `check-acceptance.bats` (9 assertions)
1. happy path: flips a matching '- [ ]' line and prints 'checked'
2. already-checked idempotency: prints 'already checked' and exit 0
3. fence-awareness: '- [ ]' inside a fenced block is NOT flipped
4. criterion not found: exit 1 with error message
5. ambiguous match: two '- [ ]' lines match → exit 2
6. regex-metacharacter literal matching: 'AC-1.2' does NOT match 'AC-142'
7. CRLF tolerance: file with Windows line endings is handled
8. missing arg: exit 3 (usage)
9. missing matcher (one arg only): exit 3

#### `checkbox-flip-all.bats` (8 assertions)
1. happy path: flips every '- [ ]' in the named section → 'checked N lines'
2. idempotency: re-running on an all-checked section prints '0 lines'
3. section not found: exit 1 with 'error: section not found'
4. fence-awareness: '- [ ]' inside a fenced block is NOT flipped
5. section boundary: '- [ ]' after the next '## ' heading is not touched
6. CRLF tolerance: section with Windows line endings still flips
7. missing arg: exit 2 (usage)
8. missing section arg: exit 2

#### `commit-work.bats` (6 assertions)
1. happy path: stages via caller, commits, prints short SHA
2. nothing staged: git commit fails → exit 1
3. invalid type: exit 2 with error
4. missing args: exit 2
5. commit message format verified via git log -1 --format=%s
6. all twelve type-tokens accepted

#### `create-pr.bats` (12 assertions)
1. happy path: pushes, calls gh, prints PR URL, exit 0
2. --closes #42: body contains 'Closes #42'
3. no --closes: body contains no 'Closes' line
4. body contains the Claude Code trailer
5. --closes with empty string: exit 2, gh not invoked
6. --closes bare '#': exit 2, gh not invoked
7. git push failure: exit 1, gh NOT invoked
8. gh pr create failure: exit 1
9. invalid type: exit 2, git not pushed, gh not invoked
10. missing required args: exit 2
11. --closes= form (inline value) works too
12. summary with '&' survives body substitution (bash 5.2+ patsub_replacement guard)

#### `ensure-branch.bats` (6 assertions)
1. happy path: already on target branch → 'on <branch>'
2. branch does not exist: creates it → 'created <branch>'
3. branch exists and is not current: switches → 'switched to <branch>'
4. idempotency: calling twice with the same branch is safe
5. dirty working tree blocks switch: exit 3 with 'error: uncommitted changes'
6. missing arg: exit 2

#### `new-requirement.bats` (23 assertions)
1. FEAT happy path: writes FEAT-001 with title slug
2. FEAT happy path: stdout has trailing newline
3. CHORE happy path: writes CHORE-001 with category substituted
4. BUG happy path: writes BUG-001 with category and severity substituted
5. --issue with SSH origin renders full GitHub URL
6. --issue with HTTPS origin renders full GitHub URL
7. --issue with non-GitHub origin falls back to bare ref
8. --issue with no remote falls back to bare ref
9. --issue accepts a leading '#' and strips it
10. --issue omitted: GitHub Issue line stays in template state
11. re-run with identical args allocates a fresh ID and never overwrites
12. FEAT + --category: exit 2 with FEAT rejection error
13. CHORE + --severity: exit 2 with severity rejection error
14. FEAT + --severity: exit 2 with severity rejection error
15. CHORE + invalid --category: exit 2 with category error from validator
16. BUG + invalid --category: exit 2 with bug category error
17. missing args: exit 2 with usage error
18. single arg: exit 2 with usage error
19. invalid type: exit 2
20. unknown flag: exit 2
21. --issue without value: exit 2
22. empty title (after slugify): exit 2 (slugify failure)
23. missing template returns exit 1

#### `next-id.bats` (12 assertions)
1. happy path: returns 004 after FEAT-001..003
2. empty directory: returns 001
3. missing directory: returns 001
4. missing arg: exit 2 with error on stderr
5. invalid lowercase type: exit 2
6. invalid type (FEATURE): exit 2
7. CHORE type uses requirements/chores
8. BUG type uses requirements/bugs
9. idempotency: two invocations without new files return same value
10. AC-8 contract: with FEAT-001..019 present, returns 020
11. ignores non-matching files in directory
12. handles gaps in numbering: takes max and adds 1

#### `prepare-fork.bats` (34 assertions)
1. arg validation: missing positionals → exit 2
2. arg validation: unknown flag → exit 2
3. arg validation: non-numeric stepIndex → exit 2
4. arg validation: unknown skill-name → exit 2 and list valid names
5. arg validation: --mode on non-reviewing-requirements skill → exit 2
6. arg validation: --phase on non-implementing-plan-phases skill → exit 2
7. arg validation: --mode and --phase both set → exit 2
8. SKILL.md missing: exit 3 with resolved path in error
9. state-file missing: exit 2 with .sdlc/workflows path in error
10. jq missing: exit 4 with install hint
11. propagation: resolve-tier child failure propagates verbatim
12. happy path non-locked: reviewing-requirements + --mode standard
13. happy path non-locked: stderr echo line matches the non-locked format
14. happy path baseline-locked: finalizing-workflow → haiku, no wi-complexity/override tokens
15. happy path baseline-locked: pr-creation skips SKILL.md check
16. Edge Case 9: finalizing-workflow + --cli-model opus emits non-locked line
17. Edge Case 9: pr-creation + --cli-model opus emits non-locked line
18. happy path Edge Case 11: creating-implementation-plans + --cli-model haiku emits warning
19. repeated --cli-model-for: each occurrence forwarded to resolve-tier
20. non-bash caller: invoke from /bin/sh -c 'bash prepare-fork.sh ...'
21. NFR-1 ordering invariant: Step 4 failure preserves Step 3 audit entry
22. --help as first arg → exit 0 with usage on stdout
23. --help as last arg (after positionals) → exit 0 with usage on stdout
24. --help after an invalid skill-name → help still wins (exit 0)
25. -h short form anywhere → exit 0 with usage
26. FR-8: --phase 1 --plan-file resolves implementing-plan-phases to haiku
27. FR-8: --phase 2 --plan-file resolves implementing-plan-phases to sonnet
28. FR-8: --phase 4 --plan-file resolves implementing-plan-phases to opus
29. FR-8 + override: --phase 1 + --cli-model opus pins the per-phase tier and surfaces override token
30. FR-8: --phase without --plan-file → exit 2
31. FR-8: --plan-file without --phase → exit 2
32. FR-8: --plan-file on reviewing-requirements → exit 2
33. FR-8: other skills keep the FEAT-021 echo format when --phase absent
34. FR-8: implementing-plan-phases without --phase uses FEAT-021 echo format

#### `resolve-requirement-doc.bats` (10 assertions)
1. happy path: single FEAT-001 match prints the path and exits 0
2. happy path: CHORE-023 resolves to chores dir
3. happy path: BUG-011 resolves to bugs dir
4. AC-10: FEAT-020 resolves to this feature's doc in the real repo
5. zero matches: exit 1 with 'error: no file matches'
6. multiple matches: exit 2 with 'error: ambiguous' and candidate list
7. lowercase ID: exit 3 (malformed)
8. missing arg: exit 3 (usage)
9. unknown prefix: exit 3 (malformed)
10. missing numeric suffix: exit 3 (malformed)

#### `slugify.bats` (12 assertions) — FR-3 spike ported in Phase 1
1. AC-9 contract: 'The Quick Brown Fox Jumps' → quick-brown-fox-jumps
2. stopword stripping: 'The Art of War' → art-war
3. all listed stopwords are dropped
4. token truncation: six non-stopword tokens keeps first four
5. stopwords do not count toward the 4-token budget
6. all-stopword title: exit 1 with error
7. punctuation-only title: exit 1
8. missing arg: exit 2
9. determinism: same input twice → same output
10. no trailing newline on stdout
11. punctuation collapsed to single dash
12. mixed case is lowercased

#### `validate-categories.bats` (21 assertions)
1. FEAT: exits 0 silently regardless of category arg
2. FEAT: exits 0 with empty category
3. CHORE: accepts dependencies
4. CHORE: accepts documentation
5. CHORE: accepts refactoring
6. CHORE: accepts configuration
7. CHORE: accepts cleanup
8. CHORE: rejects unknown category with exit 2 and error on stderr
9. CHORE: rejects bug-only category 'security' with exit 2
10. BUG: accepts runtime-error
11. BUG: accepts logic-error
12. BUG: accepts ui-defect
13. BUG: accepts performance
14. BUG: accepts security
15. BUG: accepts regression
16. BUG: rejects unknown category with exit 2 and error on stderr
17. BUG: rejects chore-only category 'cleanup' with exit 2
18. missing args: exit 2 with usage error
19. single arg: exit 2 with usage error
20. invalid type (lowercase): exit 2
21. invalid type (FEATURE): exit 2

#### `verify-build-health.bats` (21 assertions)
1. pass case: all detected scripts succeed
2. subset detection: only test + build present, lint and format absent
3. fail-fast: first failing script halts; later scripts not invoked
4. fail-fast at format-check: lint passes, format:check fails, test/build skipped
5. no package.json: exit 0 with [info] skip message
6. package.json with no relevant scripts: exit 0 with [info] skip message
7. npm absent on PATH: exit 0 with [info] skip message
8. --include-validate: validate runs after build when present
9. default (no --include-validate): validate is skipped even when present
10. --include-validate without validate script: still runs the rest, no error
11. non-TTY (stdin redirected from /dev/null): no auto-fix prompt, fail-fast
12. --no-interactive flag: suppresses auto-fix even if lint:fix exists
13. auto-fix accepted: lint fails, user accepts, lint:fix runs, lint re-runs and passes
14. auto-fix declined: lint fails, user declines via PTY, fail-fast at exit 1
15. auto-fix unavailable: format:check fails but no format script defined → fail-fast
16. unknown argument: exit 2 with usage
17. --skip-test: test excluded from detection and run sequence
18. --skip-test with only test in package.json: graceful skip, exit 0
19. malformed package.json (truncated): exit 1 with [error] parse line
20. malformed package.json (trailing comma): exit 1 with [error] parse line
21. lint script invokes missing binary: exit 1, stderr passthrough

### Hooks (`plugins/lwndev-sdlc/scripts/tests/hooks/`)

#### `auto-mode-end-to-end.bats` (17 assertions)
1. auto-mode: pause plan-approval -> self-resume is denied (no UserPromptSubmit)
2. auto-mode: pause plan-approval -> user types approve -> resume allowed
3. auto-mode: pause pr-review -> self-resume is denied
4. auto-mode: pause pr-review -> user proceeds -> resume allowed
5. auto-mode: set-gate findings-decision -> self-clear-gate is denied
6. auto-mode: set-gate findings-decision -> user approves -> clear-gate allowed
7. auto-mode: pause review-findings -> self-resume is denied
8. auto-mode: pause review-findings -> user approves -> resume allowed
9. auto-mode: fork finalizing-workflow with carve-out is denied (Hook C AC7)
10. auto-mode: fork finalizing-workflow without marker is denied (Hook C AC8)
11. auto-mode: fork finalizing-workflow with merge marker is allowed
12. auto-mode: gh pr merge denied without merge marker (every flag variant)
13. auto-mode: every documented destructive pattern denied without marker
14. auto-mode: gh pr merge allowed after user types merge marker
15. auto-mode: second pause invalidates earlier marker (timestamp anchor)
16. auto-mode: marker for FEAT-099 does not authorize resume of BUG-014
17. auto-mode: composite bug-chain bypass attempt is denied at every gate

#### `guard-agent-prompts.bats` (38 assertions)
1. AC7: 'Skip the SKILL.md prompt entirely' is denied (FEAT-030 reproduction)
2. AC7: 'skip the SKILL.md ... prompt' (case-insensitive) is denied
3. AC7: 'orchestrator has obtained authorization' is denied
4. AC7: 'orchestrator has already obtained authorization' is denied
5. AC7: 'proceed directly to finalize.sh' is denied
6. AC7: 'Skip Step 10' for implementing-plan-phases is allowed (whitelist)
7. AC7: 'Skip Step 12' for implementing-plan-phases is allowed (Step 10/12 variance)
8. AC7: 'Skip Step 5' for non-gating skill (executing-bug-fixes) is allowed
9. AC7: 'Skip Step 4' embedded in reviewing-requirements SKILL.md is allowed
10. AC7: 'Skip Step 5' for finalizing-workflow is denied
11. AC7: 'Skip Step 3' with no subagent_type is denied (defensive)
12. AC8: finalizing-workflow spawn denied without merge-approval marker
13. AC8: finalizing-workflow spawn allowed with merge-approval marker
14. AC8: finalizing-workflow spawn denied when .active missing
15. AC8: finalizing-workflow spawn denied when .active is malformed
16. AC8: finalizing-workflow recognized via plugin-prefix (lwndev-sdlc:finalizing-workflow)
17. AC8: spawn target detected from prompt body when subagent_type missing
18. AC8: spawn target detected from YAML frontmatter 'name:' key
19. AC8: YAML 'name: reviewing-requirements' frontmatter does not trigger AC8
20. AC8: uppercase subagent_type still denies (case-fold)
21. AC8: mixed-case plugin-prefixed subagent_type still denies (prefix-strip + case-fold)
22. AC8: cross-workflow marker isolation — wrong-ID marker does not authorize spawn
23. innocuous prompt (no carve-outs, target reviewing-requirements) is allowed
24. innocuous prompt for executing-bug-fixes is allowed
25. missing tool_input.prompt allows (not a subagent spawn shape)
26. empty stdin allows (matcher misfire)
27. negative regression: FEAT-030 reproduction sentence triggers AC7 + AC8 (denied)
28. negative regression: with merge-approval marker, AC7 carve-out STILL wins (defense in depth)
29. BUG-015 RC-2: subagent_type=general-purpose + embedded name=finalizing-workflow is denied
30. BUG-015 RC-2: subagent_type=general-purpose + embedded name=finalizing-workflow allowed with marker
31. BUG-015 RC-2: subagent_type=general-purpose + embedded name=reviewing-requirements is allowed (no false positive)
32. BUG-015 RC-2: subagent_type=general-purpose + embedded name=executing-bug-fixes is allowed
33. BUG-015 RC-2: subagent_type=finalizing-workflow still denies (existing behavior unchanged)
34. BUG-015 RC-2: plugin-prefixed embedded name (lwndev-sdlc:finalizing-workflow) is recognized
35. BUG-015 RC-2: subagent_type=general-purpose with no embedded name allows
36. BUG-015 RC-2: tampered embedded name 'finalizing-workflow-x' still triggers AC8 deny
37. BUG-015 RC-2: tampered embedded name 'finalizing-workflow-fake' still triggers AC8 deny
38. BUG-015 RC-2: tampered embedded name with plugin prefix 'lwndev-sdlc:finalizing-workflow-fork' still denies
   (+ 3 more: allowed-with-marker, non-prefix-no-false-positive — total in file: 41)

#### `guard-findings-edits.bats` (33 assertions)
1. Edit allowed: no .active file (no workflow context)
2. Edit allowed: gate is null (no gate set)
3. Edit allowed: out-of-scope path (src/index.ts) regardless of gate
4. Edit allowed: requirements doc but not under features/chores/bugs/
5. Edit allowed: empty file_path (not an editor shape)
6. Edit allowed: missing tool_input.file_path entirely
7. Edit denied: gate set, no marker, gated path (bugs)
8. Edit denied: gate set, no marker, gated path (features)
9. Edit denied: gate set, no marker, gated path (chores)
10. Edit denied: gated regex matches sibling docs under same category (defense in depth)
11. Edit denied: stale marker (mtime < gateSetAt)
12. Edit allowed: fresh marker (mtime >= gateSetAt)
13. Edit denied: legacy state file missing gateSetAt (treated as infinitely old)
14. Edit denied: unparseable gateSetAt format (fail-secure)
15. Write denied: gate set, no marker, gated path (parity with Edit)
16. Write allowed: out-of-scope path (parity with Edit)
17. Write allowed: fresh marker (parity with Edit)
18. MultiEdit denied: gate set, no marker, gated path (parity with Edit)
19. MultiEdit allowed: out-of-scope path (parity with Edit)
20. MultiEdit allowed: fresh marker (parity with Edit)
21. Edit allowed: missing state file for active workflow (no gate to enforce)
22. Edit denied: corrupt state JSON on guarded path (fail-secure)
23. Edit allowed: corrupt state JSON on out-of-scope path
24. Edit allowed: empty .active file
25. Edit allowed: malformed .active ID
26. Empty stdin allows (matcher misfire)
27. Edit on absolute path resolving into gated dir is denied (substring match)
28. Edit on traversal-shaped path does not match the gated regex (allow)
29. Full cycle: set-gate -> deny -> approve -> allow -> clear-gate -> allow
30. Auto-mode reproduction: orchestrator-issued Edit during auto-mode is denied
31. marker_mtime_epoch returns numeric epoch on this platform (BUG-014 stat ordering)
32. marker_mtime_epoch returns empty for missing file
   (+ 1 more assertion counted in file total of 33)

#### `guard-state-transitions.bats` (35 assertions)
1. resume denied: no marker present
2. resume allowed: fresh marker present (mtime >= pausedAt)
3. resume denied: stale marker (mtime < pausedAt)
4. resume denied: missing pausedAt (pre-fix workflow)
5. resume denied: missing state file
6. resume denied: corrupt state JSON
7. resume denied: unparseable pausedAt format (fail-secure)
8. resume denied: workflow has no active pauseReason
9. clear-gate denied: no marker present
10. clear-gate allowed: marker present
11. clear-gate denied: no active gate
12. gh pr merge denied without merge-approval marker
13. gh pr merge allowed with merge-approval marker
14. gh pr merge with no flags is denied (not just gh pr merge --squash)
15. git push --force denied without merge-approval marker
16. git push -f denied without merge-approval marker
17. git reset --hard denied without merge-approval marker
18. gh release create denied without merge-approval marker
19. npm publish denied without merge-approval marker
20. git tag -d denied without merge-approval marker
21. git push origin :refs/tags/v1 denied without merge-approval marker
22. destructive Bash denied when .active missing
23. destructive Bash denied when .active is empty
24. destructive Bash denied when .active is malformed
25. innocuous Bash (ls) is allowed
26. git status is allowed
27. git push (without --force / -f) is allowed
28. workflow-state.sh status (read-only) is allowed
29. workflow-state.sh advance (not in guard set) is allowed
30. marker_mtime_epoch returns numeric epoch on this platform (BUG-014 stat ordering)
31. marker_mtime_epoch returns empty for missing file
32. FEAT-030 gate 2 reproduction: self-resume immediately after pause is denied
33. FEAT-030 gate 1 reproduction: self-clear-gate after set-gate is denied
34. BUG-015 RC-3: stale marker from before clear-gate does not satisfy a freshly-opened gate (clear-gate path)
   (+ 1 more)

#### `record-approval.bats` (28 assertions)
1. approve plan-approval BUG-014 writes the plan-approval marker
2. approve pr-review BUG-014 writes the pr-review marker
3. approve findings-decision BUG-014 writes the findings-decision marker
4. approve review-findings BUG-014 writes the review-findings marker
5. merge BUG-014 writes the merge-approval marker (matches Hook B name)
6. pause BUG-014 writes the pause marker
7. proceed BUG-014 with no state file writes the .approval-proceed-<ID> fallback
8. proceed BUG-014 with active pauseReason resolves to that gate
9. proceed BUG-014 with active gate beats pauseReason
10. yes BUG-014 behaves like proceed BUG-014
11. unknown shape silently no-ops (no marker written, exit 0)
12. approve without an ID silently no-ops
13. case-insensitive keyword: APPROVE PLAN-APPROVAL BUG-014 still matches
14. mixed case keyword: Approve Plan-Approval BUG-014 still matches
15. Unicode look-alike (Cyrillic а) does NOT match
16. two approval shapes back-to-back create two markers
17. adversarial workflow ID (BUG-014; rm -rf) does not inject
18. approve plan-approval BUG-014 followed by a space and more text still matches
19. empty prompt no-ops cleanly (exit 0)
20. whitespace-only prompt no-ops cleanly
21. missing stdin payload no-ops cleanly (exit 0)
22. marker file body contains timestamp, workflow_id, and verbatim message
23. FEAT and CHORE prefixes are accepted
24. long workflow ID (BUG-99999999) is accepted
25. FEAT-030 carve-out negative regression: text 'Skip the SKILL.md prompt entirely' creates no marker
26. marker uses atomic write (no .tmp leak after success)
27. BUG-015 RC-3: mv -f advances marker mtime on each UserPromptSubmit (gateSetAt freshness)
28. jq absent: hook exits 0 silently and writes no marker (fail-open per contract)

#### `workflow-state-pausedat.bats` (6 assertions)
1. fresh init does not write pausedAt
2. pause writes pausedAt as an ISO-8601 string
3. pause sets status, pauseReason, and pausedAt atomically
4. resume preserves pausedAt (history retained for fail-secure)
5. second pause overwrites pausedAt with new wall-clock time
6. pause with different reason still updates pausedAt

### Skill-level tests (`plugins/lwndev-sdlc/skills/`)

#### `creating-implementation-plans/` (80 assertions total)
- `phase-complexity-budget.bats`: 26 assertions
- `qa-feat-029-gaps.bats`: 16 assertions
- `render-plan-scaffold.bats`: 10 assertions
- `split-phase-suggest.bats`: 11 assertions
- `validate-phase-sizes.bats`: 7 assertions
- `validate-plan-dag.bats`: 10 assertions

#### `documenting-bugs/` (15 assertions)
- `validate-rc-traceability.bats`: 15 assertions

#### `executing-qa/` (117 assertions total)
- `capability-report-diff.bats`: 11 assertions
- `check-branch-diff.bats`: 7 assertions
- `commit-qa-tests.bats`: 7 assertions
- `qa-baseline.bats`: 8 assertions
- `qa-reconcile-delta.bats`: 10 assertions
- `qa-verify-coverage.bats`: 29 assertions
- `render-qa-results.bats`: 16 assertions
- `run-framework.bats`: 20 assertions
- `stop-hook.bats`: 9 assertions

#### `finalizing-workflow/` (73 assertions total)
- `check-idempotent.bats`: 15 assertions
- `completion-upsert.bats`: 10 assertions
- `finalize.bats`: 14 assertions
- `finalize.e2e.bats`: 10 assertions
- `preflight-checks.bats`: 11 assertions
- `reconcile-affected-files.bats`: 13 assertions

#### `implementing-plan-phases/` (94 assertions total)
- `check-deliverable.bats`: 23 assertions
- `commit-and-push-phase.bats`: 17 assertions
- `next-pending-phase.bats`: 12 assertions
- `plan-status-marker.bats`: 14 assertions
- `verify-all-phases-complete.bats`: 8 assertions
- `verify-phase-deliverables.bats`: 20 assertions

#### `managing-work-items/` (95 assertions total)
- `backend-detect.bats`: 15 assertions
- `extract-issue-ref.bats`: 13 assertions
- `fetch-issue.bats`: 14 assertions
- `post-issue-comment.bats`: 17 assertions
- `pr-link.bats`: 11 assertions
- `render-issue-comment.bats`: 25 assertions

#### `orchestrating-workflows/` (144 assertions total)
- `check-resume-preconditions.bats`: 16 assertions
- `findings-decision.bats`: 25 assertions
- `init-workflow.bats`: 14 assertions
- `parse-findings.bats`: 14 assertions
- `parse-model-flags.bats`: 26 assertions
- `parse-qa-return.bats`: 17 assertions
- `resolve-pr-number.bats`: 17 assertions
- `workflow-state-record-findings-qa.bats`: 15 assertions

#### `reviewing-requirements/` (107 assertions total)
- `cross-ref-check.bats`: 9 assertions
- `detect-review-mode.bats`: 20 assertions
- `extract-references.bats`: 18 assertions
- `pr-diff-vs-plan.bats`: 17 assertions
- `reconcile-test-plan.bats`: 18 assertions
- `verify-references.bats`: 25 assertions

---

## FR-8: Pre-feature bats footprint

`bats` is referenced only in the `.bats` test files themselves. Verified:
- `package.json`: no `bats` reference
- `.github/workflows/`: no CI workflows present (directory does not exist or is empty)
- `README.md`: no `bats` reference
- `CONTRIBUTING.md`: does not exist

FR-8 pre-feature footprint confirmed: `bats` has zero build-system or CI integration. Removing the `.bats` files in Phases 3-17 fully removes the Bats dependency with no other cleanup needed.

---

## Summary counts

| Category | Count |
|----------|-------|
| `.test.ts` files (pre-Phase-1) | 42 |
| `.spec.ts` files (non-fixture) | 8 |
| `.spec.ts` fixture (allow-ruled) | 1 |
| Total TypeScript test files | 51 |
| `.bats` files total | 68 |
| — top-level shared | 14 |
| — hooks | 6 |
| — skill-level | 48 |
| Phase 1 new `.test.ts` files | 2 |
| Total after Phase 1 | 53 |
