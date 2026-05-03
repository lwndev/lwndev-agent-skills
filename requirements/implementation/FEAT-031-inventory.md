# Test layout consolidation — research notes

Originally produced as the Phase 1 inventory for [#235](https://github.com/lwndev/lwndev-marketplace/issues/235) (closed; abandoned Bats→Vitest port). Preserved as research input for [#255](https://github.com/lwndev/lwndev-marketplace/issues/255). Sections specific to the abandoned port have been removed; the remaining content is fact-finding that applies regardless of approach.

---

## Working-tree scan

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

### `.spec.ts` files (8 files + 1 fixture)

**Important correction**: An earlier framing claimed these were "silently never run." In Vitest v3, the `testMatch: ['**/__tests__/**/*.test.ts']` pattern also matches `.spec.ts` files (Vitest v3 glob matching includes `.spec.ts` variants). All 8 spec files below are currently running and **passing**. The fixture entry is excluded via the explicit `exclude` rule.

| File | Currently runs | Tests passing | Recommendation |
|------|---------------|---------------|----------------|
| `scripts/__tests__/qa-CHORE-034.spec.ts` | YES (29 tests pass) | Yes | Rename to `qa-CHORE-034.test.ts`, move to `tests/unit/` |
| `scripts/__tests__/qa-CHORE-035.spec.ts` | YES (47 tests pass) | Yes | Rename to `qa-CHORE-035.test.ts`, move to `tests/unit/` |
| `scripts/__tests__/qa-FEAT-020.spec.ts` | YES (21 tests pass) | Yes | Rename to `qa-feat-020.test.ts` (kebab-case), move to `tests/unit/` |
| `scripts/__tests__/qa-FEAT-021.spec.ts` | YES (39 tests pass) | Yes | Rename to `qa-feat-021.test.ts` (kebab-case), move to `tests/unit/` |
| `scripts/__tests__/qa-FEAT-022.spec.ts` | YES (16 tests pass) | Yes | Rename to `qa-feat-022.test.ts` (kebab-case), move to `tests/unit/` |
| `scripts/__tests__/qa-feat-029.spec.ts` | YES (5 tests pass) | Yes | Rename to `qa-feat-029.test.ts`, move to `tests/unit/` |
| `scripts/__tests__/qa-finalizing-workflow-inputs.spec.ts` | YES (14 tests pass) | Yes | Rename to `qa-finalizing-workflow-inputs.test.ts`, move to `tests/unit/` |
| `__tests__/qa-feat-030-contract.spec.ts` | YES (7 tests pass) | Yes | Rename to `qa-feat-030-contract.test.ts`, move to `tests/unit/` |
| `scripts/__tests__/fixtures/feat-030-known-buggy/__tests__/qa-buggy.spec.ts` | NO (excluded) | N/A — intentionally failing fixture | Stay-in-place allow-rule: kept as `.spec.ts`, excluded from top-level testMatch, invoked only by `feat-030-executing-qa.test.ts` as child process |

All recommendations involve rename + move with no production-code changes — tests are currently passing.

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
slugify.bats
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

---

## Convention decisions

| Convention | Decision |
|-----------|---------|
| Extension | `.test.ts` only — no `.spec.ts` (except the fixture allow-rule) |
| Casing | `kebab-case` — file names use lowercase-hyphen (e.g. `slugify.test.ts`, not `Slugify.test.ts`) |
| QA naming | `qa-<dimension>.test.ts` — per-adversarial-dimension naming (e.g. `qa-inputs.test.ts`, `qa-error-handling.test.ts`). Rationale: `executing-qa/SKILL.md:178` already emits dimension-keyed paths |

---

## Fixture subtree decisions

| Subtree | Decision | Rationale |
|---------|---------|---------|
| `scripts/__tests__/fixtures/feat-014/` | Stay-in-place (no allow-rule needed) | Contains no `.test.ts`/`.spec.ts`, only markdown data; the parent `testMatch` does not reach inside it |
| `scripts/__tests__/fixtures/feat-030-known-buggy/` | Stay-in-place with allow-rule for `__tests__/qa-buggy.spec.ts` | Intentional harness fixture; `feat-030-executing-qa.test.ts` invokes child Vitest pointed at the fixture's own `vitest.config.ts`. Must not move or the relative paths inside the harness break |
| `scripts/__tests__/fixtures/feat-030-known-buggy/vitest.config.ts` | Stay-in-place | Child target config; moving it would break the harness invocation in `feat-030-executing-qa.test.ts` |
| `scripts/__tests__/fixtures/qa-fixture/` | Relocate to `tests/fixtures/qa-fixture/` | Contains vitest config + test files; falls under the migration |
| `scripts/__tests__/fixtures/qa-fixture-empty/` | Stay-in-place | README-only; no test files |

---

## tsconfig and ESLint

**tsconfig**: Introduce `tsconfig.test.json` extending `tsconfig.json` with `include: ["tests/**/*.ts"]`. The root `tsconfig.json` keeps `rootDir: "./scripts"` and `include: ["scripts/**/*.ts"]` unchanged. ESLint `parserOptions.project` becomes `['./tsconfig.json', './tsconfig.test.json']`.

**vitest.config.ts `testMatch`**: Final state `['tests/unit/**/*.test.ts']`. The migration window may need a dual-include (`['**/__tests__/**/*.test.ts', '**/tests/unit/**/*.test.ts']`) until all files have moved, then narrow.

**`qa-fixture` reconciliation**: Relocate `scripts/__tests__/fixtures/qa-fixture/` → `tests/fixtures/qa-fixture/`. Update any harness paths that reference it. The new path falls outside `tests/unit/**` so the final `testMatch` already won't match it.

---

## Husky wiring

Append `npm run validate` to `.husky/pre-commit` after the existing chain. The final hook reads:
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

## PreToolUse JSON shape reference

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

The checked-in file is `.claude/settings.json` (not `settings.local.json` which is gitignored). The existing `settings.local.json` shows a `SubagentStart` hook example that confirms the hook command receives a JSON payload piped via stdin (`cat | jq -r ...`).

---

## Bats footprint (pre-consolidation)

`bats` is referenced only in the `.bats` test files themselves. Verified:
- `package.json`: no `bats` reference
- `.github/workflows/`: no CI workflows present (directory does not exist or is empty)
- `README.md`: no `bats` reference
- `CONTRIBUTING.md`: does not exist

This finding directly informs #255's "how to install Bats for contributors" decision: there is no existing dependency declaration to update, so the consolidation feature must add one (npm devDependency wrapping bats-core, Homebrew via README contributor instructions, or detect-and-install in `npm test`).

---

## Summary counts

| Category | Count |
|----------|-------|
| `.test.ts` files | 42 |
| `.spec.ts` files (non-fixture) | 8 |
| `.spec.ts` fixture (allow-ruled) | 1 |
| Total TypeScript test files | 51 |
| `.bats` files total | 68 |
| — top-level shared | 14 |
| — hooks | 6 |
| — skill-level | 48 |
