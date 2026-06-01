# Changelog

## [1.27.3] - 2026-06-01

Maintenance release: relocates the `finalizing-workflow` write-surface guard to a reliable enforcement point. No new features or breaking changes.

### Bug Fixes

- **BUG-024:** Move the finalize write-surface guard out of the dead, forked Stop hook (which never ran) into a pre-merge in-script check (`arm-baseline.sh` + `check-write-surface.sh`), with the baseline stored in the git dir. The guard now actually blocks merges that touch the protected write surface ([#310](https://github.com/lwndev/lwndev-marketplace/pull/310)).

[1.27.3]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.27.2...lwndev-sdlc@1.27.3

## [1.27.2] - 2026-05-31

Maintenance release: one bug fix to the QA-adoption routing in the SDLC workflow skills. No new features or breaking changes.

### Bug Fixes

- **BUG-023:** Route an initial-run QA `PASS` through `addressing-qa-findings` (adopt phase) whenever committed `qa-*` test files are git-visible, instead of advancing straight to `finalizing-workflow`. Initial-PASS QA tests are now promoted into their `*.qa.*` regression siblings rather than being left on the branch to trip the FR-9 finalize gate. Updates `qa-dispatch.sh`/`detect-phase` routing to the OR-form contract and aligns the contract comments ([#308](https://github.com/lwndev/lwndev-marketplace/pull/308)).

[1.27.2]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.27.1...lwndev-sdlc@1.27.2

## [1.27.1] - 2026-05-31

Maintenance release: three bug fixes to the SDLC workflow skills plus a dependency bump. No new features or breaking changes.

### Bug Fixes

- **BUG-021:** Remove the unsupported `--project` flag from `az repos pr show`/`update` in `managing-source-control`. Azure DevOps PR view/update operations no longer fail on backends where the flag is rejected ([#305](https://github.com/lwndev/lwndev-marketplace/pull/305)).
- **BUG-022:** Cross-check workflow state in `detect-re-qa-mode.sh` so the QA loop reliably distinguishes a re-QA run from a first run, including transitive state migration ([#306](https://github.com/lwndev/lwndev-marketplace/pull/306)).
- **BUG-020:** Harden orchestrator pause-step documentation and the merge-approval gate; correct `set-gate` help text and `cmd_advance` line citations ([#297](https://github.com/lwndev/lwndev-marketplace/pull/297)).

### Chores

- **deps:** Bump `brace-expansion` to 5.0.6 to clear an npm audit advisory.

[1.27.1]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.27.0...lwndev-sdlc@1.27.1

## [1.27.0] - 2026-05-18

### Features

- **FEAT-034:** `managing-source-control` ADO PR comment support ([#286](https://github.com/lwndev/lwndev-marketplace/pull/286), closes [#280](https://github.com/lwndev/lwndev-marketplace/issues/280)). Closes the parity gap where the GitHub backend could post PR comments via `gh pr comment` but the Azure DevOps backend had no equivalent, leaving consumer skills like `/review` unable to write PR feedback on ADO-hosted repos. Adds three new dispatched scripts under `plugins/lwndev-sdlc/skills/managing-source-control/scripts/`: `pr-comment.sh` (post top-level comment or reply to thread), `list-pr-comments.sh` (emit comments as NDJSON), and a reserved `pr-comment-thread.sh` stub for inline file-line comments (Phase 2). **GitHub backend** wraps `gh pr comment <pr> --body <body>` / `--body-file <path>`; `--reply-to` is rejected with a `[warn]` graceful skip because the unified `gh` comment API has no thread-reply semantics. **Azure DevOps backend** posts via the `_apis/git/repositories/{repositoryId}/pullRequests/{pullRequestId}/threads` REST endpoint (`api-version=7.1`); resolves `repositoryId` once via `az repos show --query id -o tsv` and caches it for the call. Replies hit `…/threads/{threadId}/comments` and the script first lists the thread's existing comments to determine the most recent `parentCommentId` so replies thread visually in the ADO UI (falls back to `parentCommentId: 0` on empty threads). Body sources (`<positional>` / `--body` / `--body-file`) are mutually exclusive — passing more than one exits non-zero with `[error] body source ambiguous`. `--reply-to` requires a non-negative integer; non-numeric values exit non-zero with `[error] --reply-to must be a numeric thread id` (client-side validation, runs before backend dispatch). **NDJSON listing schema** is identical across backends (`{id, body, author, createdAt, threadId, parentCommentId, url}`), enabling consumer `jq` queries to work unchanged regardless of backend. **Coverage:** new Bats tests under `tests/bats/skills/managing-source-control/pr-comment-*.bats` and `list-pr-comments-*.bats` cover each backend with `gh`/`az` stubs, the mutual-exclusion validation, the `--reply-to` numeric check, the GitHub graceful-skip path, and the Azure DevOps `repositoryId` resolution. Round-trip integration tests under `tests/bats/skills/managing-source-control/round-trip-*.bats` are env-gated (`SDLC_INTEGRATION_TESTS=1`) so contributors without live credentials run only the unit-equivalent suite.

### Bug Fixes

- **BUG-018 (security, critical):** atomic auto-pause on advance + remove `auto-fixed` decision ([#287](https://github.com/lwndev/lwndev-marketplace/pull/287), closes [#281](https://github.com/lwndev/lwndev-marketplace/issues/281)). `workflow-state.sh advance` did not enforce pause-context steps: it marked any pending step `complete` and bumped `currentStep` without checking the step's `context` field, so the orchestrator could walk straight past plan-approval, PR-review, and other gated pauses with no `pausedAt` stamp and no approval marker. Hook B gated `resume` and `clear-gate` (BUG-014 / #244) but never fired for `advance`, leaving the same class of bypass open through a different call shape. Reproducer evidence: `.sdlc/workflows/FEAT-034.json` showed step 4 (Plan approval, `context: "pause"`) marked `complete` ~34s after step 3 finished, with top-level `pauseReason: null`, no `pausedAt`, and no `.approval-plan-approval-FEAT-034` marker. **Fix:** `cmd_advance` now inspects the step it is completing; if `context == "pause"` it atomically marks the step `complete`, sets workflow `status: "paused"`, derives `pauseReason` from the step, and stamps `pausedAt` in the same transaction — eliminating the orchestrator's responsibility to issue a separate `pause` call. Non-pause-context steps continue to advance exactly as before — no `pausedAt` is stamped, no `status` change, no behavioral regression. Subsequent `advance` calls on a paused workflow require an `.approval-<reason>-<ID>` marker plus `cmd_resume` (already Hook B-gated). **Companion fix:** `auto-fixed` is removed entirely from the `record-findings` decision whitelist in `cmd_record_findings_review`, closing the path where the orchestrator could apply review fixes without an approval marker. The remaining four decisions (`advanced` / `auto-advanced` / `user-advanced` / `paused`) are sufficient — marker-gating `auto-fixed` was considered but rejected because it left a residual call shape a future "work without stopping" reinterpretation could exploit. **Doc fix:** `orchestrating-workflows/SKILL.md` `Load-bearing carve-outs` now explicitly states that the "work without stopping for clarifying questions" system reminder does NOT apply to workflow-defined approval gates, naming all five gate identifiers (`plan-approval`, `pr-review`, `findings-decision`, `review-findings`, `merge-approval`).

- **BUG-019 (logic-error, high):** `managing-source-control` `backend-detect.sh` rejects HTTPS origin URLs with `user@host` credential prefix ([#290](https://github.com/lwndev/lwndev-marketplace/pull/290), closes [#289](https://github.com/lwndev/lwndev-marketplace/issues/289)). The AzDO HTTPS branch in `parse_azdo()` (`backend-detect.sh:72`) anchored `dev\.azure\.com/` directly after `https?://` with no allowance for an optional `<user>@` segment, so git origins persisted by the macOS credential helper (`osxkeychain` / `manager-core`) in the form `https://<user>@dev.azure.com/<org>/<project>/_git/<repo>` emitted literal `null` from `backend-detect.sh`. Downstream impact on a 1.26.0 run: `create-pr.sh` graceful-skipped, leaving the orchestrator stuck at `pr-review` pause until state was patched manually via `workflow-state.sh set-pr`; `finalizing-workflow` was similarly a no-op and required `az repos pr update --status completed` by hand to merge. `SDLC_SCM_BACKEND=azdo` did not help — by design, the env override flips the label only and still requires the origin URL to match the AzDO pattern. **Fix:** all three HTTPS regexes (`parse_azdo()` `dev.azure.com` branch, `parse_azdo()` `*.visualstudio.com` legacy branch, `parse_github()` `github.com` branch) now allow an optional `(?:[^@/]+@)?` segment between `https?://` and the host. SSH branches are unaffected — SSH origins (`git@github.com:`, `git@ssh.dev.azure.com:v3/`) do not carry an HTTP basic-auth `user@` prefix. The GitHub HTTPS branch is fixed for symmetry: a `<token>@github.com/...` origin from the same git-credential-helper persistence pattern would have hit the same gap. **Coverage:** `tests/bats/skills/managing-source-control/backend-detect.qa.bats` (adopted from the QA-phase test) covers user-prefixed variants of every affected HTTPS form.

[1.27.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.26.0...lwndev-sdlc@1.27.0

## [1.26.0] - 2026-05-17

### Features

- **FEAT-033:** new `managing-source-control` skill — multi-backend git + PR dispatch (GitHub + Azure DevOps) ([#278](https://github.com/lwndev/lwndev-marketplace/pull/278), closes [#120](https://github.com/lwndev/lwndev-marketplace/issues/120)). Closes the gap where every PR-touching script in the plugin hard-coded `gh`, locking out Azure DevOps users entirely. Adds `plugins/lwndev-sdlc/skills/managing-source-control/` — a sibling to `managing-work-items` — as the single delegation surface for all git and PR work. **Backend detection** (`backend-detect.sh`): parses `git remote get-url origin` (recognizes `github.com`, `dev.azure.com`, `*.visualstudio.com`, `ssh.dev.azure.com` `v3/<org>/<project>/<repo>` form) and honors the `SDLC_SCM_BACKEND=github|azdo` env override; emits JSON `{backend, owner|organization, project?, repo}` or literal `null` for unrecognized remotes. **Backend-agnostic scripts** (`ensure-branch.sh`, `build-branch-name.sh`, `commit-work.sh`): conventional `feat/`/`chore/`/`fix/` branch prefixes, conventional-commit-format messages, no `--no-verify`, no `git add -A`. **Dispatched PR operations** (`create-pr.sh`, `view-pr.sh`, `list-pr.sh`, `merge-pr.sh`, `pr-diff.sh`): branch on backend and forward to `gh pr ...` or `az repos pr ...`; the `az` path runs every response through `az-shape-transform.sh` to normalize Azure DevOps output to GitHub-equivalent JSON (`status`→`state`, `mergeStatus`→`mergeable`, `_links.web.href`→`url`, reconstructed `files` via `git diff --name-only`) so existing consumer `jq` queries in `preflight-checks.sh`, `reconcile-affected-files.sh`, and `detect-review-mode.sh` work unchanged. PR-diff on the Azure DevOps path resolves the base via `az repos pr show --query targetRefName` and runs `git diff origin/<base>...HEAD` because `az` lacks a `gh pr diff` equivalent. **Auto-close issue linkage** — GitHub emits `Closes #<N>`; Azure DevOps emits `AB#<id>` for Azure Boards or the Jira issue key when the work-item backend is Jira (both Azure Boards and Jira auto-close on `--status completed`). **Consumer refactor (FR-11):** `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `finalizing-workflow`, `reviewing-requirements` (including `verify-references.sh` which now delegates `gh issue view` to `managing-work-items/scripts/fetch-issue.sh`), and `orchestrating-workflows/scripts/resolve-pr-number.sh` all updated to call the new skill's scripts — both script bodies and inline `${CLAUDE_PLUGIN_ROOT}/...` path references in SKILL.md prose. **NFR-5 enforcing check:** new `scripts/validate-no-inline-scm.ts` invoked by `npm run validate` greps `plugins/lwndev-sdlc/skills/**` and `plugins/lwndev-sdlc/scripts/**` for `gh pr`, `gh issue`, `az repos`, `az boards` and fails the build if any reference lives outside `managing-source-control/scripts/` or `managing-work-items/scripts/`. Documenting the rule alone was insufficient; the check now blocks regressions. **Orchestrator integration:** `orchestrating-workflows` `Read`s `managing-source-control/SKILL.md` once at workflow start (inline pattern, mirrors `managing-work-items`, not an Agent fork). **Graceful degradation (NFR-1):** missing `gh` or `az` CLI / auth failure triggers a `[warn]` line and a skip — same contract as `managing-work-items`. **Coverage:** unit tests under `tests/unit/managing-source-control.test.ts` validate frontmatter and layout; Bats tests under `tests/bats/skills/managing-source-control/` cover backend detection, env-var override, each dispatcher with `gh` and `az` stubs, and each graceful-skip path.

### Bug Fixes

- **test:** disable git auto-gc in `tests/unit/release.test.ts` to avoid a CI rm-race where parallel git operations triggered background gc and removed pack files mid-test.

[1.26.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.25.0...lwndev-sdlc@1.26.0

## [1.25.0] - 2026-05-10

### Features

- **FEAT-032:** ephemeral QA tests, fix-and-adopt loop, and merge-time safety-net ([#276](https://github.com/lwndev/lwndev-marketplace/pull/276)). Closes the gap where adversarial `executing-qa` runs left `qa-*` test files committed on the branch with no defined adoption path, so they either leaked past merge or were silently dropped. Three changes combine to make QA tests first-class but ephemeral on the branch. **(1) New `addressing-qa-findings` skill** — developer-persona skill that consumes `ISSUES-FOUND` verdicts, reproduces failing QA tests locally, writes the production fix, re-validates, and (in a separate adopt phase after re-QA `PASS`) renames each `qa-*.test.ts` / `qa-*.bats` to a `*.qa.*` sibling next to its peer test via `git mv`. Adoption is the sole owner of QA-test deletion (the move *is* the deletion, FR-13). The skill auto-detects fix vs. adopt phase from the workflow state triple `{qaLastVerdict, qaFixAttempts, adoptedTests}` — no phase argument is required. **(2) Orchestrator verdict-branching + re-QA loop** — `orchestrating-workflows` now branches on the QA verdict: `PASS` (first run) and `EXPLORATORY-ONLY` advance directly to finalize; `ISSUES-FOUND` forks `addressing-qa-findings` (fix), then re-invokes `executing-qa` in re-QA mode, then on `PASS` forks `addressing-qa-findings` (adopt) before advancing. Loop cap is 2 fix attempts (configurable via `--qa-loop-cap <N>` on resume). On exhaustion the workflow pauses with `qa-loop-exhausted`; `ERROR` verdicts pause with `qa-error`. The pause-reason enum is extended; resume dispatch handles all four new pause reasons (`qa-error`, `qa-loop-exhausted`, `fix-suite-failed`, `adoption-failed`). **(3) FR-9 safety-net at merge time** — `finalizing-workflow/scripts/preflight-checks.sh` runs after the build-health gate and blocks merge if any tracked file matches the v1 ephemeral-QA glob set (`tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, `tests/bats/qa/qa-*.bats`). Adopted `*.qa.*` siblings pass cleanly; untracked files do not block. Globs are anchored to canonical ephemeral paths so permanent infrastructure tests under `tests/bats/skills/<skill>/` (e.g. `qa-dispatch.bats`, `qa-baseline.bats`) do not trip the gate. **executing-qa re-QA mode** — when invoked after a fix attempt, `executing-qa` detects re-QA mode from the `.sdlc/qa/.executing-qa-baseline-{ID}` marker and overwrites (does not version) the QA results artifact. The artifact embeds each finding's failing test source under a `## Reproduction` block so the fix skill can replay the exact failure. **Workflow-state schema** adds `qaFixAttempts`, `qaLastVerdict`, `adoptedTests`. **CLAUDE.md** documents the new lifecycle, the `qa-*` → `*.qa.*` naming convention, the FR-9 lockstep with FR-5 dispatch (Edge Case 17 — pytest/go-test globs are intentionally absent until adopt-qa-test gains real dispatch for those frameworks), and the parity-assertion guidance for directories that may receive `*.qa.*` siblings. **Acceptance:** an end-to-end Bats fixture (`tests/bats/skills/orchestrating-workflows/qa-loop-end-to-end*.bats`) drives the full `ISSUES-FOUND → fix → re-QA → adopt → finalize` cycle against a known-buggy fixture under `tests/fixtures/feat-032-known-buggy/` and asserts no `qa-*` file remains post-adopt.

### Bug Fixes

- **BUG-017:** harden test-count assertions to derive counts from disk ([#275](https://github.com/lwndev/lwndev-marketplace/pull/275)). The previous parity assertions in `tests/unit/build.test.ts` and `tests/unit/shared-scripts.test.ts` were brittle to additions: a new test file or a new shared script silently broke the count check downstream of an unrelated PR. Counts are now derived from disk in `beforeAll` so the assertion always reflects current state, and the tautological count comparison in `build.test.ts` was dropped. Companion regression fix derives skill counts from disk and moves the heavy `load` calls to `beforeAll` so a single failure does not cascade.

### Chores

- **CHORE-038:** enable Vitest `fileParallelism` ([#274](https://github.com/lwndev/lwndev-marketplace/pull/274)). Test files now run in parallel by default. Tests that mutate `plugins/` were isolated into temp directories (using `mkdtemp` outside `plugins/`) so they do not race with other parallel test files. The `argument-hint` `readdir` counts now filter `_`-prefixed entries to match the underlying skill loader's hidden-file convention. CLAUDE.md documents the parallelism contract: tests that need to drive `npm run validate` against a fixture tree must set `PLUGINS_DIR=<tmp>` so `scripts/lib/constants.ts` reads it at module load. Wall-time impact: the unit suite drops from ~1:45 to ~13s on an 8-core dev machine.

[1.25.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.24.0...lwndev-sdlc@1.25.0

## [1.24.0] - 2026-05-03

### Features

- **FEAT-031:** consolidate test layout under `tests/` with validator + PreToolUse hook ([#256](https://github.com/lwndev/lwndev-marketplace/pull/256), closes [#255](https://github.com/lwndev/lwndev-marketplace/issues/255)). Every test file in the repo now lives under a single `tests/` root with two runner-scoped leaves: `tests/unit/` for Vitest (`.test.ts` only, kebab-case) and `tests/bats/` for Bats (`shared/`, `shared/hooks/`, `skills/<skill>/`, `qa/`). Shared TS fixtures live at `tests/fixtures/`. **Why it ships in the plugin release:** prior to this feature, `.bats` files lived under `plugins/lwndev-sdlc/scripts/tests/` and `plugins/lwndev-sdlc/skills/<skill>/scripts/tests/`, so every `/plugin install lwndev-sdlc` shipped ~156 KB of contributor-only test residue (~68 `.bats` + 51 `.test.ts`/`.spec.ts` + ~36 fixture files). Post-feature: zero test files under `plugins/` — `find plugins/lwndev-sdlc -type f \( -name '*.bats' -o -name '*.test.ts' -o -name '*.spec.ts' \)` returns empty, and `find plugins/lwndev-sdlc -type d -name fixtures` returns empty. **Phases 1–2 — relocation:** 42 `.test.ts` files moved from `scripts/__tests__/` to `tests/unit/`; 8 `.spec.ts` files renamed to `.test.ts` with kebab-case normalization (the `feat-030-known-buggy` fixture is the documented `.spec.ts` exception); 68 `.bats` files relocated out of `plugins/` with every `BATS_TEST_DIRNAME`-anchored path expression rewritten to span the new gap. **Phase 3 — runner unification:** `npm test` now runs `test:unit && test:bats`; `tsconfig.test.json`, `vitest.config.ts` `testMatch`, ESLint config, lint/format globs, and `lint-staged` all updated; `bats` ships as an npm devDep (`^1.13.0`) so contributors get `npx bats` automatically after `npm install`; `test:bats` parallelizes across files via `bats --jobs 8` (requires GNU `parallel`). **Phase 5 — layout validator:** `scripts/validate-test-layout.ts` + shared rule module (`scripts/test-layout-rules.ts`) fail the build on misplaced test files; `npm run validate` now enforces the layout. **Phase 6 — PreToolUse hook:** `scripts/hooks/validate-test-layout-hook.ts` blocks `Write`/`Edit`/`MultiEdit` of test files outside the canonical leaves at the harness level (fails open on malformed JSON to avoid false-positive blocks). **Phase 7 — doc alignment:** `CLAUDE.md` and every `SKILL.md` referencing test placement updated to the new layout. **Acceptance snapshot:** 1561 Vitest tests across 51 files (+13 from the new validator coverage, zero pre-existing tests dropped); `npm test` total wall time ~2:55 (Vitest 54.57s + Bats segment, within the 2× pre-feature Vitest-only NFR-4 budget); `du -sh plugins/lwndev-sdlc` ≈ 1.3 MB with zero test residue.

### Bug Fixes

- **BUG-016 (regression, critical):** restore shared-scripts parity by relocating QA fixture ([#268](https://github.com/lwndev/lwndev-marketplace/pull/268), closes [#260](https://github.com/lwndev/lwndev-marketplace/issues/260)). CHORE-037 (PR #259) added a husky-hook QA fixture at `tests/bats/shared/qa-CHORE-037-husky-hooks.bats`, raising the directory's `.bats` count to 15 and breaking the parity assertion at `tests/unit/shared-scripts.test.ts:106` (which requires the count to equal `CANONICAL_SCRIPTS.length` = 14). Every PR built against `main` failed until the parity was restored. **RC-1:** the QA fixture was placed in the parity-checked directory because CLAUDE.md's "Skill Authoring" guidance directs shell-script tests to `tests/bats/shared/<name>.bats` for shared/hook coverage, and "shared/hook" was the closest-matching leaf for husky-hook QA. Neither the layout validator nor CLAUDE.md surfaced the parity invariant at the placement point. **Fix:** relocate the fixture to `tests/bats/qa/qa-CHORE-037-husky-hooks.bats`; the recursive `tests/bats` glob in `package.json` continues to exercise it. Verification: `npm test` clean (1589/1589); 10/10 adversarial QA tests pass.

### Chores

- **CHORE-037 (configuration):** move heavy test suite from pre-commit to pre-push ([#259](https://github.com/lwndev/lwndev-marketplace/pull/259), closes [#257](https://github.com/lwndev/lwndev-marketplace/issues/257)). Splits the husky hook tiers so `.husky/pre-commit` runs only fast checks (`npx lint-staged`, `npm run lint`, `npm run format:check`) and a new `.husky/pre-push` runs the heavyweight gate (`npm test`, `npm audit --audit-level=high`, `npm run validate` in that order). Eliminates the multi-minute per-commit tax that punished marker, doc, and WIP commits and triggered an orchestrator stop-hook polling spiral. Doc-only commits (e.g., editing a `requirements/**/*.md` file) now complete in under 5 seconds locally; pushes containing a deliberately failing Vitest or Bats test are blocked by the pre-push hook. CI workflow unchanged — CI remains the authoritative gate. Path-based scoping ("skip tests for markdown-only commits") was considered and rejected because this repo has load-bearing markdown fixtures (SKILL.md files consumed by `validate()`, requirement-doc fixtures parsed by skill scripts, templates under `assets/`); a static include/exclude rule is unsafe.

[1.24.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.23.2...lwndev-sdlc@1.24.0

## [1.23.2] - 2026-05-02

### Bug Fixes

- **BUG-015 (security):** close the general-purpose-fork edit bypass on the findings-decision gate ([#252](https://github.com/lwndev/lwndev-marketplace/pull/252)). Four reinforcing fixes harden the FEAT-014 confirmation chain so a forked subagent cannot tamper with findings outputs or smuggle an unapproved skill past the gate. **RC-1** extends `guard-state-transitions.sh` to block `Edit` / `Write` / `MultiEdit` against findings-decision artifacts unless a fresh approval marker is present (closing the silent-edit path that allowed a fork to rewrite a `pause-errors` decision into `advance`). **RC-2** teaches Hook C to extract the embedded `name:` frontmatter from inline `SKILL.md` payloads *before* matching `subagent_type`, so a payload claiming a different identity than its embedded contract cannot ride the carve-out. **RC-3** records `gateSetAt` on every gate write so the marker-freshness comparison uses the gate's own timestamp anchor instead of process-start, eliminating the mtime-skew window that allowed a stale marker to satisfy the freshness check. The follow-up commit additionally closes a residual prefix-tampered embedded-name bypass and ports the BSD/Linux mtime unit tests added in BUG-014 to the new gate path. Test surface: bats coverage for `guard-findings-edits` plus an embedded-name parity suite covering all three RC paths.

### Chores

- **CHORE-036:** extract `documenting-*` skill shell into shared scripts ([#250](https://github.com/lwndev/lwndev-marketplace/pull/250)). The three `documenting-*` skills (features, chores, bugs) shared the same boilerplate — new-requirement scaffolding, category validation, requirement-context traceability checks — open-coded inside each `SKILL.md`. The chore lifts that shell into three plugin-scoped scripts (`plugins/lwndev-sdlc/scripts/new-requirement.sh`, `validate-categories.sh`, `validate-rc-traceability.sh`) with bats coverage for each, and rewrites the three `SKILL.md` files to call them. The public contract is unchanged; the change is purely a token-cost and maintenance reduction across the three skills.

[1.23.2]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.23.1...lwndev-sdlc@1.23.2

## [1.23.1] - 2026-04-28

### Bug Fixes

- **BUG-014 (security):** add a four-hook confirmation-gate defense layer that closes the gap where state transitions could advance without a real user approval ([#247](https://github.com/lwndev/lwndev-marketplace/pull/247)). Hook A (`record-approval.sh`, UserPromptSubmit) writes approval markers; Hook B (`guard-state-transitions.sh`) blocks `resume`, `clear-gate`, and destructive Bash without a fresh marker, using a `pausedAt` timestamp anchor newly added to `workflow-state.sh cmd_pause`; Hook C (`guard-agent-prompts.sh`) enforces carve-outs and confirmation-owning-skill checks on agent prompts; Hook D ships a managed-settings template for destructive-Bash defense-in-depth at the harness level. Hooks A/B/C are wired in `plugins/lwndev-sdlc/hooks/hooks.json`. The approval-marker grammar is documented in `orchestrating-workflows/SKILL.md`, and an end-to-end auto-mode bats regression covers the full flow (the suite also fixed a BSD `date` UTC handling bug discovered while writing it).
- **BUG-014 (portability):** make the marker mtime check work on Linux ([#248](https://github.com/lwndev/lwndev-marketplace/pull/248)). The mtime epoch derivation relied on BSD `stat` flags; the fix resolves the platform-specific `stat` arguments so the gate behaves identically on Linux CI and macOS dev machines. Covered by a new test for `marker_mtime_epoch` stat ordering.

### Tests

- Bump global vitest `testTimeout` to 15s to stabilize flaky `execSync`-based tests on slower CI runners.
- New adversarial vitest suite for BUG-014 covering the hook chain and marker grammar.

[1.23.1]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.23.0...lwndev-sdlc@1.23.1

## [1.23.0] - 2026-04-26

### Features

- **FEAT-030:** consolidate `executing-qa` scripted producers, agent replacement, and report-only enforcement ([#242](https://github.com/lwndev/lwndev-marketplace/issues/242)). Closes three overlapping issues — [#187](https://github.com/lwndev/lwndev-marketplace/issues/187) (scripted producers), [#192](https://github.com/lwndev/lwndev-marketplace/issues/192) (agent replacement), [#208](https://github.com/lwndev/lwndev-marketplace/issues/208) (report-only enforcement) — into one PR because all three touch the same files (`executing-qa/SKILL.md`, `stop-hook.sh`, the new producers, `workflow-state.sh`) and the same data path (test-runner output → artifact → workflow-state findings → orchestrator); splitting would have churned the QA return contract across three half-built merges. **Phase 1 — contract lock (FR-1):** new `plugins/lwndev-sdlc/skills/executing-qa/references/qa-return-contract.md` documents the three-part contract producers must satisfy — artifact schema (`version: 2` frontmatter + required sections), final-message line (`Verdict: <PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY> | Passed: <N> | Failed: <N> | Errored: <N>` as the skill's last response line, analogous to the fork-to-orchestrator return contract used elsewhere), and workflow-state findings JSON shape (`{verdict, passed, failed, errored, summary}`). **Phase 2 — six producer scripts (FR-3 through FR-8):** `capability-report-diff.sh`, `check-branch-diff.sh`, `run-framework.sh`, `qa-reconcile-delta.sh` (single shared implementation also satisfying [#192](https://github.com/lwndev/lwndev-marketplace/issues/192) item 11.2), `render-qa-results.sh`, `commit-qa-tests.sh` — 71 bats tests. **Phase 3 — agent replacement (FR-9 / [#192](https://github.com/lwndev/lwndev-marketplace/issues/192)):** new `qa-verify-coverage.sh` replaces both `qa-verifier.md` and `qa-reconciliation-agent.md` (deleted from `agents/`); 29 bats tests. **Phase 4 — stop-hook FR-10 diff guard + `qa-baseline.sh` ([#208](https://github.com/lwndev/lwndev-marketplace/issues/208) scope item 2):** `stop-hook.sh` rejects runs that edit files outside the framework's test root, closing the silent-production-edits defect that allowed `executing-qa` to make failing tests pass by modifying production code; 17 bats tests. **Phase 5 — orchestrator findings persistence ([#208](https://github.com/lwndev/lwndev-marketplace/issues/208) scope items 3–5):** `workflow-state.sh record-findings --type qa|review` persists the FR-1 JSON shape on the QA step entry; new `parse-qa-return.sh` extracts the final-message line; orchestrator SKILL.md FR-14 wires the parse → persist → advance handoff so the orchestrator acts on QA findings programmatically; 32 bats tests. **Phase 6 — SKILL.md rewrite + non-remediation rule (FR-2 / FR-13):** `executing-qa/SKILL.md` rewritten to wire every Phase 2 script and adopt the `## Report-Only Mode` rule that explicitly prohibits production-code edits during QA runs; cross-skill cross-references to the new contract added throughout; regression vitest fixture at `scripts/__tests__/feat-030-executing-qa.test.ts` covers the ISSUES-FOUND verdict, no-production-file-edits invariant, failing-test-name listing, FR-1 findings persistence, valid-artifact stop-hook pass, and FR-10 simulated-misbehavior block. **Per-run runtime payoff:** ~2,350–3,450 input tokens saved per `executing-qa` invocation (six producer scripts collapse the deterministic prose; agent replacement removes two subagent fork costs). **Test surface:** 149 new bats tests (71 + 29 + 17 + 32) across `executing-qa/scripts/tests/` and `orchestrating-workflows/scripts/tests/`, plus the 6-scenario vitest regression suite. Full repo `npm test` and `npm run validate` clean. Merged via PR [#243](https://github.com/lwndev/lwndev-marketplace/pull/243).

[1.23.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.22.0...lwndev-sdlc@1.23.0

## [1.22.0] - 2026-04-25

### Features

- **FEAT-029:** `creating-implementation-plans` scripts + per-phase tier reduction ([#190](https://github.com/lwndev/lwndev-marketplace/issues/190)). Two compounding savings levers land in one feature. **Lever 1 — prose-to-script for plan creation:** five new skill-scoped shell scripts under `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/` collapse the deterministic prose inside `creating-implementation-plans` — `render-plan-scaffold.sh` (FR-1, plan-skeleton renderer accepting comma-separated `<FEAT-IDs>` with optional `--enforce-phase-budget`), `validate-plan-dag.sh` (FR-2, cycle / unresolved-dependency check across phase blocks), `phase-complexity-budget.sh` (FR-3, per-phase complexity scorer emitting `{phase, tier, signals, overBudget}` for every phase or a single `--phase N`), `split-phase-suggest.sh` (FR-4, advisory 2–3-phase split proposer for over-budget phases), and `validate-phase-sizes.sh` (FR-5, gate that fails the plan when any phase exceeds budget without an override). **Lever 2 — per-phase tier reduction:** `workflow-state.sh resolve-tier` (FR-6) gains `--phase N --plan-file <path>` so each `implementing-plan-phases` fork resolves its own tier from the scored phase block; `prepare-fork.sh` (FR-7) threads `--phase` / `--plan-file` through to the resolver; the `implementing-plan-phases` baseline drops from `sonnet` to `haiku` so mechanical phases run on Haiku and Sonnet / Opus stay reserved for phases that genuinely warrant them; `classify-post-plan` is rewritten as a `max` aggregator across phase tiers, retiring the old `1→low / 2–3→medium / 4+→high` raw-phase-count anti-pattern (Edge Case 8 in `references/model-selection.md`) where splitting a phase for clarity actively *upgraded* the tier. **Per-workflow runtime payoff:** ~550–750 input tokens saved per plan creation from the prose-to-script work alone; the per-phase tier lever is the bigger savings — a typical 4-phase feature where 3 phases qualify as low and 1 as medium drops fork cost from 4×Opus to 3×Haiku + 1×Sonnet, an order-of-magnitude reduction on `implementing-plan-phases` fork calls. NFR-4 from FEAT-014 ("fresh default invocation on a typical chore or low-severity bug produces zero Opus fork calls") now extends to features whose phases are individually mechanical. FR-10 / NFR-4 / NFR-6 also rewrite `creating-implementation-plans/SKILL.md` and `references/model-selection.md` to reflect the new behaviour, with `SKILL.md` reduced **22.3%** by lean-down compression. Test surface: 90+ bats tests across the five per-script fixtures plus a vitest adversarial suite at `scripts/__tests__/qa-feat-029.test.ts`. Merged via PR [#240](https://github.com/lwndev/lwndev-marketplace/pull/240).

### Bug Fixes

- **finalizing-workflow:** extract last line of preflight output for JSON parsing — `preflight-checks.sh --no-interactive` could emit additional context lines before the JSON contract; the workflow now isolates the final line for parsing so trailing diagnostics no longer break the gate.

[1.22.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.21.1...lwndev-sdlc@1.22.0

## [1.21.1] - 2026-04-25

### Bug Fixes

- **BUG-013:** phase-completion skills no longer declare success without running the repo's lint/format/test gates ([#212](https://github.com/lwndev/lwndev-marketplace/issues/212)). Adds shared `plugins/lwndev-sdlc/scripts/verify-build-health.sh` that detects available `package.json` scripts (`lint`, `format:check`, `test`, `build`; `validate` opt-in via `--include-validate`), runs each that exists, and halts on the first non-zero exit. Wired into all six affected skills with the documented interactive vs non-interactive split: `executing-chores` Step 7, `executing-bug-fixes` Step 9, `implementing-plan-phases` (lint/format added to `verify-phase-deliverables.sh`'s JSON contract), `executing-qa` (new Step 5.5, `--no-interactive`), `finalizing-workflow` `preflight-checks.sh` (`--no-interactive`), and `releasing-plugins` (new Step 8 between changelog and push). The auto-fix branch (`lint:fix` / `format`) is reachable only at the four interactive sites; QA and finalize fail-fast. 21-test bats suite plus 7-scenario vitest adversarial suite at `scripts/__tests__/qa-bug-013.test.ts`. Closes the gap that was leaking prettier/eslint errors to release branches and `main` (CI runs 24781710973, 24781373957, 24781373952). Merged via PR [#237](https://github.com/lwndev/lwndev-marketplace/pull/237).
- **security:** bump `postcss` from 8.5.8 to 8.5.10 to clear `npm audit` advisory [GHSA-qx2v-qp2m-jg93](https://github.com/advisories/GHSA-qx2v-qp2m-jg93) (XSS via unescaped `</style>` in CSS Stringify output). Transitive devDependency only.

[1.21.1]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.21.0...lwndev-sdlc@1.21.1

## [1.21.0] - 2026-04-25

### Features

- **FEAT-028:** `orchestrating-workflows` findings / resume / remainder scripts ([#186](https://github.com/lwndev/lwndev-marketplace/issues/186)). Closes the remaining prose hot-spots in the orchestrator that were not already collapsed by FEAT-021's `prepare-fork.sh` (item 9.2 of the [#179](https://github.com/lwndev/lwndev-marketplace/issues/179) prose-to-script backlog). Ships six new skill-scoped scripts under `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/` plus one new subcommand on the existing `workflow-state.sh`: `parse-model-flags.sh` (FR-1, argv partition for the FEAT-014 `--model` / `--complexity` / `--model-for` flag set with positional-independent parsing, last-wins repetition for `--model-for`, and explicit `=`-form rejection), `parse-findings.sh` (FR-2, `reviewing-requirements` subagent-output parser emitting `{counts, individual[]}` with the W4 errors-only-no-warn invariant — counts.warnings + counts.info > 0 is the only path that triggers the `[warn] parse-findings: counts non-zero but no individual findings parsed` stderr line), `findings-decision.sh` (FR-3, three-way Decision-Flow resolver — `advance` / `auto-advance` / `prompt-user` / `pause-errors` — applying the chain-type + complexity gate from `references/reviewing-requirements-flow.md`), `resolve-pr-number.sh` (FR-4, post-fork PR-number extraction from subagent output with `gh pr list --head <branch>` fallback, last-match-wins disambiguation), `init-workflow.sh` (FR-5, new-workflow composite — active marker write, ID read, state init, complexity classify, advance step 1 — collapsing all five into one script call across feature / chore / bug chains), `check-resume-preconditions.sh` (FR-6, Resume Procedure steps 1–5 emitting `{type, status, pauseReason, currentStep, chainTable, complexityStage, complexity}` for the resume gate), and `workflow-state.sh set-model-override` (FR-7, persists `modelOverride` tier between pause and resume — bare tiers `haiku` / `sonnet` / `opus` only, downgrade explicitly permitted per FEAT-014 FR-12, replacing the manual `jq '.modelOverride = "opus"'` incantation that `references/model-selection.md` Migration Option 4b called out by name). FR-8 rewrites SKILL.md and four reference documents (`reviewing-requirements-flow.md`, `chain-procedures.md`, `step-execution-details.md`, `model-selection.md`) to replace the mechanical prose with one-line script pointers — SKILL.md collapses **net -14.3%** lines (254 → 218), comfortably above the ≥ 8% target; per-reference reductions all met or exceeded the same threshold (the public contract — Quick Start dispatch, fork-return shape, Decision Flow action table, Resume Procedure step 6 — stays prose). FR-9 caller audit confirmed no orchestrator-internal invocation shape changes required and no other skill files modified. **Per-workflow runtime payoff:** ~1,500–2,500 input tokens saved per feature workflow (FR-1 ~200 × 1, FR-2 ~400–600 × 2–3, FR-3 ~300 × 2–3, FR-4 ~150 × 0–2, FR-5 ~300 × 1, FR-6 ~400 × 0–1 on resume, FR-7 ~150 × 0–1 on manual override). Savings compound across resume paths, every `reviewing-requirements` fork (twice or three times per workflow), every `executing-chores` / `executing-bug-fixes` fork, and every workflow start — and the orchestrator is the hottest file in the plugin, so every line of removed prose pays back on every single run. **Test surface:** 104 bats tests ship across the six per-script fixtures (covering happy path, documented edge cases, the W4 errors-only-no-warn invariant, the chainTable == type invariant for all three workflow types, fence/CRLF awareness, and PATH-shadowed `jq` / `gh` / `workflow-state.sh` stubs); a complementary 35-scenario adversarial vitest suite at `scripts/__tests__/qa-feat-028.test.ts` probes state transitions and cross-cutting invariants the bats fixtures do not duplicate (equals-sign rejection, unknown-flag rejection, malformed `--model-for` tier, last-wins repetition, positional-interleave, `set -euo pipefail` strict-mode compatibility, `env -i` compatibility, missing state file, `chainTable == type` across all three workflow types). Full regression: 1422 vitest tests + 104 orchestrating-workflows bats tests + all other plugin bats suites green; 13/13 plugins validate via `npm run validate`. Nine PR review issues addressed in-branch before merge; merged via PR [#233](https://github.com/lwndev/lwndev-marketplace/pull/233).

[1.21.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.20.0...lwndev-sdlc@1.21.0

## [1.20.0] - 2026-04-23

### Features

- **FEAT-027:** `implementing-plan-phases` scripts ([#185](https://github.com/lwndev/lwndev-marketplace/issues/185)). Collapse the deterministic prose inside `implementing-plan-phases` into six skill-scoped shell scripts under `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/` and rewrite SKILL.md to delegate through them: `next-pending-phase.sh` (FR-1, Step 2 auto-selection with sequential + explicit `**Depends on:**` dependency forms and four JSON output shapes — happy, all-complete, resume-in-progress, blocked), `plan-status-marker.sh` (FR-2, Step 3 / Step 9 three-state transitions with idempotent `already set` no-op and fence-awareness), `check-deliverable.sh` (FR-3, Step 6 phase-scoped checkbox flip accepting both numeric index and literal substring matcher with `2`=ambiguous / `3`=missing-arg exit-code shape matching `check-acceptance.sh`), `verify-phase-deliverables.sh` (FR-4, Step 7 composite file-existence + `npm test` + `npm run build` + `npm run test:coverage` with graceful `npm`-absent degradation), `commit-and-push-phase.sh` (FR-5, Step 8 stage / commit / push with canonical `<type>(<FEAT-ID>): <phase-name> (Phase <N>)` message format, first-push vs subsequent-push upstream logic, and fail-fast push-error surfacing with `git` stderr verbatim), and `verify-all-phases-complete.sh` (FR-6, Step 10 pre-PR gate emitting `all phases complete` on success or JSON `{incomplete:[...]}` on any non-complete phase). SKILL.md rewritten from 290 → 139 lines (-52%); Steps 2 / 3 / 6-checkoff / 7 / 8-commit-push / 9 / 10-check bodies replaced with one-paragraph script pointers while the public contract (When to Use, Arguments, Quick Start, Output Style, Fork-to-orchestrator return contract, Phase Structure, Branch Naming, Push Failure Recovery, References) stays prose — the Push Failure Recovery section is promoted from inline bold inside Step 8 to a navigable `##` heading and documents the do-not-re-run-the-script caller pattern from Edge Case 11 (FR-5's step-1 sanity gate trips on a clean tree post-`git rebase`). `implementing-plan-phases` runs `N` times per feature workflow (once per phase), so the scripts amortize to an estimated **~6,900 input tokens saved per 4-phase feature workflow** — putting the savings in the same band as FEAT-022's finalize subscripts despite `implementing-plan-phases` being the highest mechanical-density skill per invocation. 90 bats tests ship across the six per-script fixtures (`scripts/tests/fixtures/` covering minimal, multi-phase, fenced-status, duplicate-phase, and explicit-dependency plans); a supplementary 36-scenario vitest suite at `scripts/__tests__/qa-feat-027.test.ts` bridges the scripts through subprocess execution with PATH-shadowing stubs for `npm`, covering adversarial dimensions (inputs, state transitions, environment, dependency failure, cross-cutting concerns). Full regression: 42 files / 1409 tests all green. FR-8 caller-audit confirmed no orchestrator fork-invocation shape changes required and no other skill files modified; `plugins/lwndev-sdlc/scripts/` directory unchanged (the plugin-shared `build-branch-name.sh` and `ensure-branch.sh` from FEAT-020 / FEAT-021 are referenced from SKILL.md Step 4 unchanged). PR #230 code-review follow-ups: `git add` failure path covered by new bats case; `verify-all-phases-complete.sh` `[error] no phase blocks found in plan` stderr exit documented in both the SKILL.md Step 10 contract and `references/step-details.md`; step-details line-286 mislabel (`**Step 10 (Update Plan Status)**` → `**Step 9**`) corrected. Merged via PR [#230](https://github.com/lwndev/lwndev-marketplace/pull/230).

[1.20.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.19.0...lwndev-sdlc@1.20.0

## [1.19.0] - 2026-04-23

### Features

- **FEAT-025:** `managing-work-items` full scripting ([#183](https://github.com/lwndev/lwndev-marketplace/issues/183)). Collapse the six-operation `managing-work-items` skill from prose-driven inline execution into six skill-scoped shell scripts under `plugins/lwndev-sdlc/skills/managing-work-items/scripts/`: `backend-detect.sh` (FR-1, issue-reference classification), `extract-issue-ref.sh` (FR-7, requirement-document extraction), `pr-link.sh` (FR-6, PR-body auto-close fragment), `render-issue-comment.sh` (FR-5, template rendering for both markdown and ADF JSON paths), `post-issue-comment.sh` (FR-5 composite — detect → render → post → graceful-skip), and `fetch-issue.sh` (fetch for pre-fill). SKILL.md rewritten to point at the scripts; the Arguments / Operations / Jira-Specific Error Handling / Graceful Degradation / Output Style sections retained unchanged. `post-issue-comment.sh` replaces ~60 lines of orchestrator-adjacent prose per invocation; across the 6+ comment posts plus `fetch` / `extract-ref` / `pr-link` per workflow, the composite saves **~2,200–2,800 input tokens per workflow run** (matches the #179 top-10 row-3 and per-skill catalogue estimate within ±10%). Every `[warn]` / `[info]` string the scripts emit matches the SKILL.md Graceful Degradation / Error Handling tables verbatim — a grep-level zero-divergence requirement (NFR-1) enforced during standard review. 95 bats tests ship alongside the scripts under `scripts/tests/` plus a 28-scenario vitest subprocess-bridge suite under `scripts/__tests__/qa-managing-work-items.test.ts` for the repo's existing CI surface. Two P0 bugs surfaced during the write-and-run loop and were fixed in-branch: invalid JSON for leading-zero GitHub refs in `backend-detect.sh` (e.g. `#007` was misclassified because leading zeros slipped through the strict-numeric regex) and `pr-link.sh` accepting empty-string arguments instead of exiting 2. Both covered by regression fixtures. `documenting-features/SKILL.md` line 38 updated to reference the `fetch-issue.sh` delegation; `documenting-chores` and `documenting-bugs` confirmed unchanged (no equivalent delegation notes present). Merged via PR [#225](https://github.com/lwndev/lwndev-marketplace/pull/225).
- **FEAT-026:** `reviewing-requirements` scripts ([#184](https://github.com/lwndev/lwndev-marketplace/issues/184)). Collapse the `reviewing-requirements` skill's deterministic prose into six skill-scoped shell scripts under `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/`: `detect-review-mode.sh` (FR-1, Step-1.5 mode precedence), `extract-references.sh` (FR-2, Step-2 four-category token extraction — file paths / identifiers / cross-refs / GitHub refs), `verify-references.sh` (FR-3, Step-3 Moved/Ambiguous/Missing/Unavailable classification loop), `cross-ref-check.sh` (FR-4, Step-7 cross-ref-only subset), `reconcile-test-plan.sh` (FR-5, Steps R1–R5 test-plan reconciliation matcher with both version-2 prose and legacy table format support), and `pr-diff-vs-plan.sh` (FR-6, Steps CR1–CR2 PR-diff-vs-plan drift detector). SKILL.md rewritten — the mode-summary table, Step 8 Present Findings, Step 9 Apply Fixes, Document Type Adaptations, and Verification Checklist sections stay prose; Steps 1.5 / 2 / 3 / 7 / R1–R5 / CR1–CR2 bodies become one-paragraph pointers at the scripts. Net reduction: 410 → 329 lines (19.76%; the FR-7 ≥ 25% target was capped by the ~200-line retain list of public contract + reasoning prose — documented as a known deviation, with the authoritative acceptance test being the NFR-4 token-savings measurement scheduled post-merge). `reviewing-requirements` runs up to 3× per workflow (standard pre-QA, test-plan reconciliation, code-review reconciliation), so the scripts amortize to an estimated **~5,350–7,250 input tokens saved per workflow run** — among the largest savings in the prose-to-script audit, including two of #179's top-10 scripts (`verify-references.sh` at row #4, `extract-references.sh` at row #7) plus the four lower-ranked scripts they compose with. 107 bats tests ship across the six per-script fixtures, including the NFR-6-mandated two-format coverage (version-2 prose + legacy table) for `reconcile-test-plan.sh`; a supplementary 17-scenario vitest suite at `scripts/__tests__/qa-reviewing-requirements.test.ts` bridges the scripts through subprocess execution for CI. The `reconcile-test-plan.sh` matcher ships inline with a TODO referencing NFR-6 — the shared `lib/match-traceability.sh` factor with `executing-qa`'s upcoming `qa-reconcile-delta.sh` is deferred to whichever PR lands second. Caller audit per FR-8 confirmed no orchestrator fork-invocation edits required. Merged via PR [#227](https://github.com/lwndev/lwndev-marketplace/pull/227).

### Bug Fixes

- **security (BUG-012):** pin the qa-fixture `vitest` to a patched range to close CVE-2025-24964 (malicious-fixture RCE). The vulnerability affected only the QA-fixture test surface — production skill code was never exposed — but the fixture is invoked by `npm test` and `npm run test:coverage`, so pinning is the low-risk path. Includes a 5-scenario QA suite exercising the patched range boundaries. Merged via PR [#218](https://github.com/lwndev/lwndev-marketplace/pull/218).

### Aggregate token-savings impact

FEAT-025 and FEAT-026 together move **~7,550–10,050 input tokens per feature workflow** off the per-invocation surface (the upper end hits when a workflow exercises all three `reviewing-requirements` modes plus the full `managing-work-items` phase-start/end cascade). Chore and bug workflows see proportionally similar savings from `managing-work-items` alone (~2,200–2,800 tokens) since they do not run the feature-only phase loop. These are input-token savings that compound across every `/workflow` invocation — the 10–30 runs/week this plugin typically sees translates to tens of thousands of tokens saved per week.

[1.19.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.18.0...lwndev-sdlc@1.19.0

## [1.18.0] - 2026-04-22

### Features

- **FEAT-024:** Input-token optimization rollout to the remaining twelve `lwndev-sdlc` skills ([#203](https://github.com/lwndev/lwndev-marketplace/issues/203)), the sister effort to FEAT-023's output-token rollout and the operationalization of the CHORE-035 pilot in `orchestrating-workflows`. Each target SKILL.md was compressed using the three-axis template: (1) FR-1 lite-style prose compression — filler / hedging removed, full sentences retained where pronoun antecedents would otherwise be lost, code blocks / commands / flags / paths / anchor IDs / table headers untouched, every CHORE-034 load-bearing carve-out preserved verbatim; (2) FR-2 heavy-narrative relocation — `reviewing-requirements` Phase 7 created `references/standard-review-steps.md` (Steps 3–7 of standard-review mode, 37 lines moved off the per-invocation surface) with a single-sentence inline pointer left at the relocation site; the other eleven skills had no FR-2 candidates exceeding the operationalized ~25-line threshold; (3) FR-3 natural collapse — `managing-work-items` Phase 5 collapsed the Graceful Degradation / Error Handling tables; the other eleven skills recorded FR-3 as a justified no-op. The FEAT-023 `## Output Style` section installed in 1.17.0 was preserved character-for-character in every target skill per FR-4 (verified by 12 ai-skills-manager `validate()` cases plus a canonical-skeleton test that asserts the lite-narration-rules subsection is byte-identical across the twelve). The Edge Case 10 FR-14 Unicode-arrow self-contradiction was corrected in three target skills (`executing-chores`, `executing-bug-fixes`, `implementing-plan-phases`) — the carve-out descriptor and the inline `[model]` example now both use Unicode `→` consistently. **Headline static delta** (SKILL.md only — the per-invocation instruction surface): -89 lines (-3.45%) / -1 282 words (-5.80%) / **-8 057 chars (-5.17%) / -2 014 input tokens** (chars / 4 estimator) across the twelve compressed SKILL.md files. The all-files aggregate including the 37-line new reference file is -52 lines / -912 words / -5 217 chars (-1.66%) — net positive on disk because relocated content moved from the always-loaded surface to an on-demand reference. `managing-work-items` (-733 chars/4, -12.83%) and `reviewing-requirements` (-443 chars/4, -6.34%) carried the rollout, jointly accounting for **58.4%** of the total reduction; they share the two largest pre-change SKILL.md surfaces and were the only phases to invoke a non-FR-1 axis at scale. **Per-workflow runtime payoff** (compounded across every `/workflow` invocation): a feature chain with the typical N = 3–5 implementation phases saves roughly **2 800–3 100 input tokens per workflow**; chore and bug chains save **~2 000 tokens per workflow** each. Ships `scripts/__tests__/qa-feat-024-rollout.test.ts` with 104 regression guards (fanned out via `it.each(TARGET_SKILLS)` across the twelve target skills) covering: required Output Style subsection presence per skill (lite-rules, load-bearing carve-outs, fork-to-orchestrator return contract OR inline-execution-note variant), inline `references/*.md` pointer resolution, code-fence balance, Output Style smart-quote freedom, lite-rules Unicode-arrow carve-out compliance, per-skill `references/` ownership and git-tracking, no shared cross-skill references directory, ai-skills-manager `validate()` pass for every target skill, lite-narration-rules canonical-skeleton invariance, executing-qa exploratory-mode-branch documentation, managing-work-items inline-execution declaration, forkable-skill canonical return-contract shape enforcement, and inline-references markdown-link syntax. Two in-flight slips were caught and remediated mid-branch and inform two of the new test guards: the Phase 2 `argument-hint.test.ts` regression where prose compression dropped the literal "When argument is provided" / "When no argument is provided" phrases from `documenting-features` (fixed in `9680b07`), and the Phase 12 FR-14 carve-out half-correction in `implementing-plan-phases` where the descriptor was updated but the inline `[model]` example was not (fixed in `da9a15a`). Continues the per-skill atomic-commit pattern (NFR-2): one commit per skill plus a Phase 0 pre-flight commit and a Phase 13 grand-total aggregation commit, all on `feat/FEAT-024-input-token-optimization-rollout` and merged via PR [#215](https://github.com/lwndev/lwndev-marketplace/pull/215) (merge commit `d442134` preserves the per-phase history on `main`).

[1.18.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.17.0...lwndev-sdlc@1.18.0

## [1.17.0] - 2026-04-22

### Features

- **FEAT-023:** Output-token optimization rollout to the remaining twelve `lwndev-sdlc` skills ([#200](https://github.com/lwndev/lwndev-marketplace/issues/200)), continuing the CHORE-034 pilot in `orchestrating-workflows`. Every target skill's `SKILL.md` gains a canonical `## Output Style` section installed immediately after `## Quick Start`, pinning lite-narration rules (no preamble / no postamble / no recap / terse final lines), a load-bearing carve-out list (error messages, security warnings, interactive prompts, findings display, tagged `[info]`/`[warn]`/`[model]` logs, user-visible state transitions), and a role-appropriate return-contract subsection. Five return-contract variants land in this rollout: (1) **forked-skill standard** — `done | artifact=<path> | <note>` on success, `failed | <reason>` on failure (`creating-implementation-plans`, `executing-chores`, `executing-bug-fixes`); (2) **forked-skill with skip-PR clause** — `implementing-plan-phases` documents the orchestrator-side instruction that appends "Do NOT create a pull request..." to its fork prompt, preserving full Step 10 for standalone invocations; (3) **main-context** — end-of-turn recaps capped at one sentence (`documenting-features`, `documenting-chores`, `documenting-bugs`); (4) **main-context with Stop-hook conformance note** — structural conformance of the emitted artifact is enforced by the skill's `scripts/stop-hook.sh` instead of a fork-return shape (`documenting-qa`, `executing-qa`); (5) **inline-execution** — the `managing-work-items` variant replaces the return contract with an "Inline execution note" documenting that `done | ...` / `failed | ...` shapes do not apply (invoked directly from main context per `orchestrating-workflows/references/issue-tracking.md`, not forked). The `reviewing-requirements` exception variant emits `Found **N errors**, **N warnings**, **N info**` as the final line preceded by the full findings block (parsed by the orchestrator's Decision Flow) and marks the findings-display carve-out explicitly load-bearing. `finalizing-workflow` rolls out in an SKILL.md-only scope (no `references/` and no `assets/`); its FEAT-022 `scripts/__tests__/finalizing-workflow.test.ts` "under 80 lines" ceiling assertion was relaxed to 120 lines per NFR-3 to accommodate the rollout-wide `## Output Style` section (current: 104 lines). All nine skills with a `references/` directory were checked for fork-invocation specs per FR-3; zero matches across all reference files (API-interaction templates, example documents, per-step guidance, annotated workflow examples) — no pointers added. All ten skills with an `assets/` directory were reviewed per FR-4; every one of the twelve templates was flagged already-minimal per Edge Case 4 (pure structural skeletons, parser-load-bearing schemas, or legacy-preserved version-1 templates) — no compression applied. **Static delta** across the twelve rolled-out skills: SKILL.md +405 lines (+18.65%) / +6068 words (+37.86%) / +41459 chars (+36.25%); references and assets 0/0/0 across all 24 touched files; grand total +405 lines (+5.18%) / +6068 words (+15.92%) / +41459 chars (+15.14%). The rollout is intentionally net-positive on static surface (the instruction surface grew ~41.5 KB) to buy a per-invocation runtime payoff on every fork response, every main-context skill session, every `reviewing-requirements` response, and every `managing-work-items` inline invocation. Ships `scripts/__tests__/qa-feat-023-rollout.test.ts` with five logical regression guards (fanned out via `it.each(TARGET_SKILLS)` to 89 parameterized cases across the twelve target skills) covering presence of the `## Output Style` heading across all twelve target SKILL.md files, canonical lite-narration-rules skeleton invariance, inline-execution declaration in `managing-work-items`, forkable-skill return-contract shape enforcement (`done | artifact=...` or the `Found **N errors**...` exception), and requirements-doc measurement-table path hygiene.

[1.17.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.16.0...lwndev-sdlc@1.17.0

## [1.16.0] - 2026-04-22

### Features

- **finalizing-workflow:** `finalize.sh` + subscripts full rewrite (FEAT-022). Collapses the skill's prose ceremony (Pre-Flight + BK-1..BK-5 bookkeeping + Execution — ~228 lines of SKILL.md) into a single user confirmation plus one top-level `finalize.sh` invocation. Ships five new skill-scoped scripts under `skills/finalizing-workflow/scripts/`: `finalize.sh` (top-level composition with no-rollback invariant and unexpected-exit fallthrough), `preflight-checks.sh` (parallel 3-check with UNKNOWN-retry-once), `check-idempotent.sh` (3-condition BK-3 check, fence/CRLF-aware), `completion-upsert.sh` (BK-4.2 in-place upsert with `upserted`/`appended` stdout token), and `reconcile-affected-files.sh` (BK-4.3 diff with `<appended> <annotated>` stdout counts). SKILL.md collapses from ~228 lines to 72 lines; all BK-* prose and the Error Handling table are replaced by a short `## Usage` section that captures the branch name, shows a PR-preview confirmation, runs `finalize.sh`, and surfaces stderr verbatim on non-zero exit. Ships 71 new bats cases (9 preflight + 15 check-idempotent + 10 completion-upsert + 13 reconcile-affected-files + 14 finalize composition + 10 finalize end-to-end) plus 16 adversarial vitest cases covering shell-metachar injection, unicode-lookalike regex rejection, PR-number boundary matching, non-ASCII / CRLF preservation, and trust-boundary arg handling. Wall-clock measured at ~600ms end-to-end on the E2E fixture (down from 30–60s of LLM-driven tool calls on the prose path). [#182](https://github.com/lwndev/lwndev-marketplace/issues/182), part of the [#179](https://github.com/lwndev/lwndev-marketplace/issues/179) prose-to-script backlog.
- **branch-id-parse.sh:** add fourth classification for release branches (FEAT-022 / FR-3). Matches `^release/[a-z0-9-]+-v[0-9]+\.[0-9]+\.[0-9]+$` and emits `{"id": null, "type": "release", "dir": null}` with exit `0`. Release PRs produced by `npm run release` now finalize without the misleading `[info] … does not match workflow ID pattern` message. All three existing classifications (`feat/`, `chore/`, `fix/`) and their emitted JSON shapes are preserved unchanged — NFR-6 strict backward compatibility.

[1.16.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.15.2...lwndev-sdlc@1.16.0

## [1.15.2] - 2026-04-21

### Documentation

- **orchestrating-workflows:** Input token optimization pilot (CHORE-035). Sister effort to CHORE-034's output-token pass, this chore targets the per-invocation instruction surface loaded on every orchestrator invocation and every forked sub-agent spawn. `orchestrating-workflows/SKILL.md` prose compressed to lite style, two heavy numbered recipes relocated into new reference files (`references/forked-steps.md`, `references/reviewing-requirements-flow.md`) with single-sentence inline pointers preserved, and the three per-chain step-sequence tables (Feature / Chore / Bug) collapsed into one parameterized table plus a per-chain deltas note. Net effect on SKILL.md: −212 lines / −2240 words / −16622 chars (−43% char reduction, ~4155 input tokens saved per load). Behaviour-neutral refactor — all CHORE-034 load-bearing carve-outs (error messages, security warnings, interactive prompts, findings display, FR-14 Unicode-arrow echoes, `[info]`/`[warn]`/`[model]` tagged logs, user-visible state transitions) and the fork-to-orchestrator return contract are preserved verbatim; no skill frontmatter changes; no new or renamed skills; no state-file schema changes (step-index numbering invariant across the relocation). `scripts/__tests__/qa-CHORE-035.spec.ts` adds 47 regression guards covering inline-pointer integrity, consolidated-table row preservation, state-file step-index invariance, and CHORE-034 carve-out / fork-return-contract preservation. Rollout to the remaining twelve skills tracked in [#203](https://github.com/lwndev/lwndev-marketplace/issues/203).

[1.15.2]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.15.1...lwndev-sdlc@1.15.2

## [1.15.1] - 2026-04-21

### Documentation

- **orchestrating-workflows:** Output token optimization pilot (CHORE-034). Adds an `## Output Style` section to `orchestrating-workflows/SKILL.md` pinning lite-narration rules, a load-bearing carve-out list (error messages, security warnings, interactive prompts, findings display, FR-14 echoes, `[info]`/`[warn]`/`[model]` tagged logs, user-visible state transitions), and a three-shape fork-to-orchestrator return contract: `done | artifact=<path> | <note>` for success, `failed | <reason>` for failure, and the pre-existing `Found **N errors**, **N warnings**, **N info**` summary for `reviewing-requirements` forks. Every fork-invocation spec in `references/step-execution-details.md` now points subagents at the contract. Documentation-only — no behavioral changes, no new parsers. Captures baseline/post-change static measurements and a Learnings subsection so the same pattern can be replicated across the remaining twelve skills; rollout tracked in [#200](https://github.com/lwndev/lwndev-marketplace/issues/200).

[1.15.1]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.15.0...lwndev-sdlc@1.15.1

## [1.15.0] - 2026-04-21

### Features

- **FEAT-021:** New `plugins/lwndev-sdlc/scripts/prepare-fork.sh` helper that collapses the four-step FEAT-014 pre-fork ceremony (SKILL.md readability check, tier resolution, `modelSelections` audit-trail write, FR-14 console echo line) into a single scripted invocation at every forked SDLC step. Callers pass `<ID> <stepIndex> <skill-name>` plus optional `--mode` / `--phase` / `--cli-model` / `--cli-complexity` / `--cli-model-for` flags; the script prints the resolved tier on stdout so the orchestrator captures it with `tier=$(bash prepare-fork.sh …)` and passes it verbatim as the Agent tool's `model` parameter. Replaces ~400–600 tokens of procedural prose at ~10 fork sites per feature workflow (4,000–6,000 tokens saved per feature) while preserving the NFR-1 ordering invariant — the audit-trail write happens before the echo line so a crashed fork still leaves a trace. Baseline-locked variants (`finalizing-workflow`, `pr-creation`) emit the `baseline-locked` tag; Edge Case 11 hard-override-below-baseline downgrades emit the documented warning line.
- **FEAT-021:** `workflow-state.sh` exposes two new subcommands — `step-baseline <step-name>` and `step-baseline-locked <step-name>` — as thin wrappers around the existing internal `_step_baseline` / `_step_baseline_locked` helpers. Both are additive (new dispatch branches, no existing subcommand changes) and return tier strings (`haiku|sonnet|opus`) or boolean strings (`true|false`) on stdout. `prepare-fork.sh` Step 4 consumes these for the FR-14 echo line.
- **FEAT-021:** Orchestrator prose in `orchestrating-workflows/SKILL.md` rewritten per FR-4 — the four-step "Forked Steps" ceremony collapses into a single `prepare-fork.sh` invocation bullet; the NFR-6 Agent-tool-rejection fallback, FR-11 retry-with-tier-upgrade, and artifact validation / state-advance steps remain as prose (they are LLM-primitive operations not representable as CLI calls). Downstream docs updated: `references/model-selection.md` notes the scripted entry point; `plugins/lwndev-sdlc/scripts/README.md` adds a `prepare-fork.sh` row to the Script Table; `requirements/features/FEAT-014-adaptive-model-selection.md` links forward to FEAT-021 as its scripted composer.
- **FEAT-021:** New `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` (25 bats cases) covers the documented error taxonomy: arg validation (exit 2) across missing positionals, unknown flags, non-numeric `stepIndex`, unknown `skill-name`, `--mode` / `--phase` cross-validation; SKILL.md readability (exit 3); state-file-not-found (exit 2); jq-missing (exit 4); child propagation (exit 1+); three happy paths (non-locked, baseline-locked, baseline-locked + skip SKILL.md for `pr-creation`); Edge Case 9 (hard override off baseline-locked step); Edge Case 11 downgrade warning; repeated `--cli-model-for`; `/bin/sh` caller; the NFR-1 ordering invariant (Step 4 fails → Step 3 audit entry still present); and `--help` precedence across five positional-/flag-ordering permutations. A companion adversarial suite `scripts/__tests__/qa-FEAT-021.spec.ts` (39 vitest cases) probes trust boundaries, malformed-ID / non-numeric-`stepIndex` matrices, argv injection, oversized `stepIndex` round-trip, concurrent invocations, retry audit-trail preservation, non-UTF8 locale em-dash byte preservation, and documents two non-blocking environment findings as passing assertions (chmod 0400 atomic-rename bypass; fallback `CLAUDE_PLUGIN_ROOT` derivation not symlink-aware).

### Bug Fixes

- **FEAT-021:** `step-baseline` / `step-baseline-locked` subcommand exit codes aligned to the `workflow-state.sh` validation-error convention (exit `1` on unknown step-name, exit `2` on missing arg). The initial implementation returned inconsistent codes that confused `prepare-fork.sh`'s propagation logic.
- **FEAT-021:** `resolve-tier` now accumulates repeated `--cli-model-for` flags correctly per Edge Case 6 — the first matching flag wins, flags for unrelated steps pass through silently. Previously a second occurrence for the same step overwrote the first without honoring argv ordering.
- **FEAT-021:** `prepare-fork.sh` Edge Case 9 echo format fixed — a hard override that pushes a baseline-locked step (`finalizing-workflow`, `pr-creation`) off its baseline now emits the non-locked echo variant with the `override=` token instead of retaining the `baseline-locked` tag. The jq-missing error message (exit 4) now carries a distinct wording from the state-file-read error (also exit 4) so callers can diagnose without inspecting the second subcommand's stderr.
- **FEAT-021:** `prepare-fork.sh` SKILL.md readability check skipped for `pr-creation` — this step-name is reserved in the Fork Step-Name Map for baseline resolution but has no `skills/pr-creation/` directory because PR creation is an inline orchestrator operation, not a forked skill. The bats fixture covers the canonical exception.

[1.15.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.14.0...lwndev-sdlc@1.15.0

## [1.14.0] - 2026-04-21

### Features

- **FEAT-020:** New `plugins/lwndev-sdlc/scripts/` plugin-shared script layer with ten cross-cutting shell utilities ([#180](https://github.com/lwndev/lwndev-marketplace/issues/180)): `next-id.sh` (ID allocation), `slugify.sh` (title → kebab slug, stopword-aware), `resolve-requirement-doc.sh` (ID → doc path), `build-branch-name.sh` (type/ID/summary → canonical branch name), `ensure-branch.sh` (create-or-switch with dirty-tree guard), `check-acceptance.sh` (fence-aware single-checkbox flip with literal-substring matching), `checkbox-flip-all.sh` (fence-aware section-wide flip with CRLF-preserving rewrite), `commit-work.sh` (conventional-commit emitter — caller stages), `create-pr.sh` (push + `gh pr create` with envsubst-free `pr-body.tmpl` template), and `branch-id-parse.sh` (branch-name → `{id, type, dir}` JSON with `jq`-absent fallback). Each script has a `bats` fixture under `scripts/tests/` covering happy path, documented error exits, idempotency, fence-awareness, CRLF tolerance, and shell-metacharacter safety; the full suite is green under `shellcheck -S warning` and bash 3.2 (macOS default) and 5.2+ (Ubuntu CI).
- **FEAT-020:** Eleven consumer skill SKILL.md files now invoke these scripts as one-line `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh" …` calls, replacing the 80–400-token prose recipes they previously duplicated. Adopters: `documenting-features`, `documenting-chores`, `documenting-bugs` (AC-11 next-id, AC-12 slugify); `reviewing-requirements` × 3 modes, `creating-implementation-plans`, `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `executing-qa`, `finalizing-workflow` (AC-13 resolve-requirement-doc); `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes` (AC-14 build-branch-name, AC-15 ensure-branch); plus targeted replacements for `check-acceptance.sh`, `checkbox-flip-all.sh`, `commit-work.sh`, `create-pr.sh`, and `branch-id-parse.sh` in the skills that need them. The orchestrator's resume-from-branch fallback also uses `branch-id-parse.sh`.
- **FEAT-020:** New `scripts/__tests__/shared-scripts.test.ts` vitest integration suite (35 cases) asserting filesystem-level invariants — directory layout, executable-bit on every script, usage-error sanity via `spawnSync`, `pr-body.tmpl` asset presence, and a one-to-one script-to-bats-fixture count. A companion adversarial suite `scripts/__tests__/qa-FEAT-020.spec.ts` (21 cases) probes CRLF round-trip preservation, language-tagged/tilde-fence awareness, regex-metachar literal matching, concurrent `next-id.sh` invocation, shell-metacharacter safety in body substitution, `jq`-absent fallback, symlinked `${BASH_SOURCE%/*}` resolution, and non-default-locale handling.

### Bug Fixes

- **FEAT-020:** `checkbox-flip-all.sh` now detects the input file's line-ending style on read and restores it on write (per the FEAT-019 "normalize on read and restore the original ending on write" rule). The initial implementation stripped CRLFs before the awk rewrite, silently downgrading Windows-authored docs to LF; this is fixed and backed by QA round-trip scenarios in `qa-FEAT-020.spec.ts`.
- **FEAT-020:** `create-pr.sh` disables the `patsub_replacement` shopt at entry so literal `&` in user-supplied summaries survives body substitution on bash 5.2+ (Ubuntu CI default). Without this guard, bash 5.2's new sed-style `&` semantics re-expand ampersands into the matched `${SUMMARY}` placeholder and corrupt the PR body. A dedicated `bats` case and the qa shell-metacharacter-safety scenario both assert the fix.

### Scope notes

- `plugin.json` and this CHANGELOG are the release-surface changes. No skill frontmatter changes; no new or renamed skills; no agent changes.
- Consumer skills that adopted the shared scripts retain identical observable behaviour — only prose is replaced with an equivalent `bash` invocation. Any workflow that worked against v1.13.0 continues to work against v1.14.0.

[1.14.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.13.0...lwndev-sdlc@1.14.0

## [1.13.0] - 2026-04-20

### Features

- **FEAT-019:** `finalizing-workflow` gains a `## Pre-Merge Bookkeeping` section that performs four mechanical updates to the active requirement document before `gh pr merge` runs ([#169](https://github.com/lwndev/lwndev-marketplace/issues/169)). The skill derives the work-item ID from the current branch name (`feat/FEAT-*`, `chore/CHORE-*`, `fix/BUG-*`), locates the matching requirement doc via glob, and — unless the doc is already finalized (idempotency check) — flips `## Acceptance Criteria` checkboxes from `[ ]` to `[x]`, upserts a `## Completion` block with today's UTC date and the PR link, and reconciles `## Affected Files` against `gh pr view --json files` (additions appended; drops annotated `(planned but not modified)`). Bookkeeping produces a single `chore({ID}): finalize requirement document` commit and pushes it before merge; non-matching branch names and missing docs skip bookkeeping gracefully (benign skip), while push failure aborts the merge. `allowed-tools` frontmatter gains `Edit` and `Glob` to support the new work. BK-3 and BK-4 are defined to be line-ending-agnostic (handle both `\n` and `\r\n`) and fenced-code-block aware (illustrative `- [ ]` examples and `## Acceptance Criteria` headings inside fenced blocks are correctly ignored) — these robustness rules were validated by the adversarial QA run that shipped alongside the feature.
- **FEAT-019:** New `scripts/__tests__/finalizing-workflow.test.ts` with 66 tests covering SKILL.md structural shape, unit-level correctness of the bookkeeping helpers (branch parsing, glob resolution, idempotency, AC checkoff, Completion upsert, Affected Files reconciliation, commit-message format), and end-to-end integration scenarios (happy path, idempotency re-run, `gh` partial failure, `gh` total failure, push-failure abort, non-matching-branch skip). Complements the adversarial spec `qa-finalizing-workflow-inputs.spec.ts` (14 P0 Inputs tests surfacing CRLF and fenced-code boundary cases).

### Scope notes

- `executing-qa/SKILL.md` is unchanged by this release. The pre-FEAT-018 write-back reconciliation loop it used to contain was already removed in v1.12.0; FEAT-019 does not reintroduce any `executing-qa` edits.
- The bookkeeping behavior applies only to workflows whose branch names follow the canonical `feat/FEAT-*-`, `chore/CHORE-*-`, or `fix/BUG-*-` conventions. Release branches (`release/...`) are intentionally skipped so the plugin's own releases do not attempt to bookkeep themselves.

[1.13.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.12.1...lwndev-sdlc@1.13.0

## [1.12.1] - 2026-04-20

### Documentation

- Plugin README, root README, and CLAUDE.md refreshed to reflect the v1.12.0 state: the two new skills (`managing-work-items`, `orchestrating-workflows`) and second agent (`qa-reconciliation-agent`) shipped via FEAT-018 are now listed; the shared library inventory, release/test-skill scripts, and full npm command set are documented; and the workflow chain diagrams now show the reconciliation steps in their correct positions.

[1.12.1]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.12.0...lwndev-sdlc@1.12.1

## [1.12.0] - 2026-04-19

### Features

- **FEAT-018:** QA skills redesigned around an executable oracle ([#170](https://github.com/lwndev/lwndev-marketplace/issues/170)). `executing-qa` now writes and runs real adversarial tests in the consumer repo's detected framework (vitest, jest, pytest, or go-test), grades on actual runner output, and produces a structured version-2 results artifact with verdict (`PASS | ISSUES-FOUND | ERROR | EXPLORATORY-ONLY`), reconciliation delta, and per-dimension findings. Repos without a supported framework degrade gracefully to `EXPLORATORY-ONLY` mode rather than failing. Stop hooks rewritten to validate artifact structure rather than regex-match PASS phrases.
- **FEAT-018:** `documenting-qa` now builds plans from user-summary + PR diff rather than the requirements doc, organizing scenarios by adversarial dimension (Inputs, State transitions, Environment, Dependency failure, Cross-cutting) with explicit priorities (P0/P1/P2) and execution modes. The closed-loop "verify every FR-N is mapped" Ralph loop has been removed.
- **FEAT-018:** New composable persona system — first persona (`qa`, adversarial tester) ships with a directory-based loader so future personas (a11y, security, performance) can be added without skill restructuring.
- **FEAT-018:** New `qa-reconciliation-agent` reference spec describing the bidirectional coverage-surplus / coverage-gap delta that `executing-qa` produces inline at the end of every run. `qa-verifier` rewritten around adversarial-coverage review (not closed-loop spec consistency).
- **FEAT-018:** Orchestrator chains shortened — feature `6+N+4 → 5+N+4`, chore/bug `8 → 7` steps. The test-plan reconciliation step is no longer invoked automatically by the orchestrator (FR-11 Option B). The `reviewing-requirements` test-plan reconciliation mode is preserved unchanged and remains callable standalone via `/reviewing-requirements {ID}`. Existing workflow state files with historical `Reconcile test plan` step entries or `mode: "test-plan"` audit-trail entries remain valid and queryable — no migration required.

### Compatibility notes

- Existing **v1** QA test plans (no `version: 2` frontmatter) are rejected by the new `executing-qa`. Re-run `documenting-qa` to regenerate as v2 before re-invoking `executing-qa`.
- The 34 historical v1 QA results artifacts under `qa/test-results/` are preserved unmodified. New runs are clearly distinguished by the `version: 2` frontmatter field.
- The orchestrator's main-context calling pattern for `documenting-qa` and `executing-qa` is unchanged.

[1.12.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.11.0...lwndev-sdlc@1.12.0

## [1.11.0] - 2026-04-19

### Features

- **FEAT-017:** Orchestrated workflows no longer fork a second `reviewing-requirements` subagent after PR review — `executing-qa` handles post-PR reconciliation instead ([#147](https://github.com/lwndev/lwndev-marketplace/issues/147)). The `reviewing-requirements` code-review mode remains callable standalone via `/reviewing-requirements {ID} --pr {N}` for ad-hoc drift reports. Existing workflow state files with historical `Reconcile post-review` step entries or `mode: "code-review"` audit-trail entries remain valid and queryable — no migration required. (Feature chain: one fewer step; chore/bug chains: 9 → 8 steps.)

### Chores

- **CHORE-033:** Fix skill permission prompts in plugin configuration.

[1.11.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.10.0...lwndev-sdlc@1.11.0

## [1.10.0] - 2026-04-18

### Features

- **FEAT-016:** Persist reviewing-requirements findings in workflow state ([#145](https://github.com/lwndev/lwndev-marketplace/issues/145)). Adds a `record-findings` subcommand to `workflow-state.sh` and integrates it at every decision point in the orchestrator's findings handling flow, so severity counts, decisions, and individual finding details are durably recorded in the state file after each reviewing-requirements step.

[1.10.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.9.1...lwndev-sdlc@1.10.0

## [1.9.1] - 2026-04-12

### Documentation

- **qa:** add QA test results for BUG-011

### Bug Fixes

- **orchestrating-workflows:** add gate mechanism to prevent stop-hook feedback loop during findings decisions (BUG-011)

[1.9.1]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.9.0...lwndev-sdlc@1.9.1

## [1.9.0] - 2026-04-12

### Documentation

- **qa:** add QA test results for FEAT-015
- **FEAT-015:** add requirements and QA test plan artifacts

### Bug Fixes

- **refs:** update review-findings resume handler for FEAT-015 changes

### Chores

- **FEAT-015:** mark Phase 1 complete and check off deliverables

### Features

- **FEAT-015:** add chain-type/complexity gate to findings-handling decision flow

[1.9.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.8.4...lwndev-sdlc@1.9.0

## [1.8.4] - 2026-04-12

### Documentation

- **qa:** add QA test results for CHORE-032
- **chore:** update CHORE-032 completion with PR #149

### Bug Fixes

- **refs:** update stale directional cross-references in extracted reference files

### Chores

- **refactoring:** split orchestrating-workflows SKILL.md into core + reference files

[1.8.4]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.8.3...lwndev-sdlc@1.8.4

## [1.8.3] - 2026-04-12

### Documentation

- **qa:** add QA test plan and results for BUG-010

### Bug Fixes

- **stop-hooks:** add state-file gates to `documenting-qa` and `executing-qa` stop hooks to prevent cross-fire with unrelated skills (BUG-010)

[1.8.3]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.8.2...lwndev-sdlc@1.8.3

## [1.8.2] - 2026-04-12

### Chores

- **refactoring:** tighten bug classifier and skip unnecessary fork steps (#141)

[1.8.2]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.8.1...lwndev-sdlc@1.8.2

## [1.8.1] - 2026-04-12

### Bug Fixes

- **orchestrating-workflows:** define the `managing-work-items` invocation mechanism so the v1.7.0 integration actually runs (BUG-009) ([#131](https://github.com/lwndev/lwndev-marketplace/issues/131)). Previously the orchestrator silently skipped all 11 `managing-work-items` call sites (4 operations: `fetch`, `extract-ref`, `comment`, `pr-link`) because `orchestrating-workflows/SKILL.md` prescribed the calls but never specified *how* to invoke them, and the Forked Steps recipe explicitly scoped itself to chain-table steps. The orchestrator now reads `managing-work-items/SKILL.md` once at workflow start and executes the documented `gh` / `acli` / Rovo MCP commands **inline from its main context** — no Agent-tool fork, no Skill-tool call. A new "How to Invoke `managing-work-items`" subsection documents the mechanism with runnable examples for all four operations, the Forked Steps section now explicitly excludes cross-cutting skills, `managing-work-items/SKILL.md:25` no longer carries the misleading "not directly by users" framing, mechanism-missing failures emit WARNING-level log lines distinguishable from the legitimate INFO-level empty-`issueRef` skip, and a new "Issue Tracking Verification" checklist distinguishes invocation-succeeded from gracefully-skipped from mechanism-failed states. Users should now see `phase-start` / `phase-completion` / `work-start` / `work-complete` / `bug-start` / `bug-complete` comments appear on linked GitHub issues (and Jira issues where a backend is available) on future workflows.

[1.8.1]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.8.0...lwndev-sdlc@1.8.1

## [1.8.0] - 2026-04-11

### Features

- **orchestrating-workflows:** adaptive model selection for forked subagents ([#130](https://github.com/lwndev/lwndev-marketplace/issues/130), [#132](https://github.com/lwndev/lwndev-marketplace/pull/132)). Each fork now picks its model from a two-axis policy — step baseline (`finalizing-workflow`/PR-creation on `haiku`; `reviewing-requirements`/`creating-implementation-plans`/`implementing-plan-phases`/`executing-chores`/`executing-bug-fixes` on `sonnet`) × work-item complexity (`low`/`medium`/`high` derived from chore AC count, bug severity/RC/category, or feature FR/NFR/phase counts). Routine chores and low-severity bugs run entirely on Sonnet + Haiku; only high-complexity features (many FRs, security/auth/perf NFRs, or ≥4 phases) bump to Opus. Eliminates silent Opus over-provisioning on mechanical work.
- **orchestrating-workflows:** override precedence chain with hard/soft distinction. New CLI flags `--model <tier>` (hard), `--complexity <tier>` (soft), `--model-for <step>:<tier>` (hard, per-step) plus a `.modelOverride` state field (soft) compose through the FR-5 walker: first non-null wins. Hard overrides replace the tier and can downgrade below baseline (with a warning); soft overrides are upgrade-only and respect baseline locks. `finalizing-workflow` and inline PR creation are **baseline-locked** — only hard overrides can bump them off `haiku`.
- **orchestrating-workflows:** two-stage feature classification. Feature chains compute an initial tier after step 1 (from FR/NFR signals) and re-compute after step 3 (`creating-implementation-plans`) to factor in phase count. Transition is upgrade-only and logged in the audit trail via per-entry `complexityStage: "init"|"post-plan"`. Chore and bug chains use a single init-stage classification.
- **orchestrating-workflows:** per-fork audit trail via `modelSelections` array in `.sdlc/workflows/{ID}.json`. Every fork records `{stepIndex, skill, mode, phase, tier, complexityStage, startedAt}` before invocation. Operators can answer "why did this run on Opus?" without reading orchestrator source. A one-line console echo (`[model] step N (skill, mode/phase) → tier (baseline=, wi-complexity=, override=)`) is emitted before each fork.
- **orchestrating-workflows:** retry-with-tier-upgrade on fork failure (FR-11). If a fork returns an empty artifact or hits a tool-use loop limit, the orchestrator retries once at the next tier up (`haiku → sonnet → opus`). Structured findings from `reviewing-requirements` are not treated as failures. Retry budget is 1 per fork, independent across phases.
- **orchestrating-workflows:** stage-aware, upgrade-only resume re-computation (FR-12). When resuming a paused workflow, signals are re-read and `new_tier = max(persisted, newly_computed)` — never silently downgrades. `complexityStage` never regresses.
- **workflow-state.sh:** new subcommands `set-complexity`, `get-model`, `record-model-selection`, `classify-init`, `classify-post-plan`, `resolve-tier`, `next-tier-up`, `resume-recompute`, `check-claude-version`. All mutations use atomic temp-file-and-rename. Chain walker uses dynamic length so the FR-5 precedence chain can grow without silent breakage.
- **workflow-state.sh:** silent backward-compatibility migration on read (FR-13). Pre-existing state files gain the four new fields (`complexity`, `complexityStage`, `modelOverride`, `modelSelections`) without clobbering existing data.

### Compatibility

- **Minimum Claude Code 2.1.72** required for adaptive selection. Older versions log a warning at orchestrator init and fall back to parent-model inheritance. Every fork call site has a per-call-site fallback wrapper that retries without the `model` parameter if the Agent tool rejects it.
- Tier values are always passed as aliases (`sonnet`/`opus`/`haiku`), never as full model IDs, because aliases are version-stable. Known limitation: the `[1m]` long-context Opus variant is not selectable via this mechanism.
- Sub-skill SKILL.md files are unchanged — no `context: fork` added. Requirement document templates are unchanged — no YAML frontmatter added.

### Documentation

- **orchestrating-workflows:** new `## Model Selection` section in SKILL.md documenting the step baseline matrix, work-item complexity signals, override precedence, baseline-locked exceptions, and four worked examples (low chore, low bug, medium feature with post-plan upgrade, high feature from init).
- **orchestrating-workflows:** new `references/model-selection.md` with full classification algorithm pseudocode, per-step baseline tuning guidance, `modelSelections` audit trail reading guide, migration guidance, and FR-5 rationale for why requirement docs do not gain frontmatter.

[1.8.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.7.0...lwndev-sdlc@1.8.0

## [1.7.0] - 2026-04-07

### Features

- **stop-hook:** replace keyword-based pattern exclusion with state-file scoping in releasing-plugins stop hook — uses `.sdlc/releasing/.active` and `.phase1-complete` marker files to eliminate false positives ([#125](https://github.com/lwndev/lwndev-marketplace/issues/125))

### Bug Fixes

- **stop-hook:** skip release validation for non-release messages (BUG-008) ([#124](https://github.com/lwndev/lwndev-marketplace/pull/124))

[1.7.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.6.0...lwndev-sdlc@1.7.0

## [1.6.0] - 2026-04-05

### Features

- **managing-work-items:** new skill centralizing all issue tracker operations (fetch, comment) with automatic backend detection (`#N` → GitHub Issues, `PROJ-123` → Jira) ([#119](https://github.com/lwndev/lwndev-marketplace/issues/119))
- **managing-work-items:** Jira support via tiered fallback — Rovo MCP (primary), Atlassian CLI (fallback), skip (graceful degradation)
- **managing-work-items:** Jira comment templates in Atlassian Document Format (ADF) JSON for Rovo MCP compatibility
- **managing-work-items:** consolidated GitHub issue comment templates from three execution skills into single source of truth
- **orchestrating-workflows:** integrated `managing-work-items` invocation points across feature, chore, and bug chains
- **documenting-features:** delegated issue fetch to `managing-work-items` skill
- **implementing-plan-phases:** removed inline `gh issue` operations; issue tracking delegated to orchestrator
- **executing-chores:** removed inline `gh issue` operations; issue tracking delegated to orchestrator
- **executing-bug-fixes:** removed inline `gh issue` operations; issue tracking delegated to orchestrator

[1.6.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.5.1...lwndev-sdlc@1.6.0

## [1.5.1] - 2026-03-30

### Bug Fixes

- **stop-hooks:** replace prompt-based Stop hooks with command-based hooks in `documenting-qa`, `executing-qa`, and `releasing-plugins` to eliminate intermittent JSON validation failures ([#114](https://github.com/lwndev/lwndev-marketplace/issues/114))
- **stop-hooks:** use `${CLAUDE_PLUGIN_ROOT}` for command hook paths in plugin skills
- **stop-hooks:** fix Phase 1/2 detection order in releasing-plugins stop hook

[1.5.1]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.5.0...lwndev-sdlc@1.5.1

## [1.5.0] - 2026-03-30

### Features

- **orchestrating-workflows:** add orchestrating-workflows skill with workflow state engine, stop hook, and SKILL.md orchestration logic
- **orchestrating-workflows:** add chore chain support with integration tests
- **orchestrating-workflows:** add bug chain support with integration tests

### Bug Fixes

- **orchestrator:** handle closed PRs during resume procedure
- **orchestrating-workflows:** reset failed step status on resume
- **finalizing-workflow:** add --merge flag to gh pr merge
- **orchestrating-workflows:** use `${CLAUDE_SKILL_DIR}` for workflow-state.sh paths in SKILL.md
- **orchestrating-workflows:** use `${CLAUDE_PLUGIN_ROOT}` for stop hook command path

### Chores

- Make phase commit-push mandatory without prompting
- Add review-findings gate to orchestrating-workflows
- Add full lint and format check to pre-commit hook
- Add test-skill utility script for local skill testing

[1.5.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.4.0...lwndev-sdlc@1.5.0

## [1.4.0] - 2026-03-28

### Features

- **FEAT-008:** add argument-hint support to skills (#86)
- **reviewing-requirements:** add code-review reconciliation mode (#82)

### Bug Fixes

- **QA verification:** rewrite from coverage auditor to direct entry verification, restore Errors count in output format
- **documenting-qa:** prevent excessive echo permission prompts; add retry and resilience guidance
- **security:** bump brace-expansion to patch GHSA-f886-m6hf-6m8v

### Chores

- Add finalizing-workflow skill for end-of-chain wrap-up
- Migrate test runner from Jest to Vitest
- Update workflow chains across all skills with reconciliation step labels
- Align QA templates with execution lifecycle
- Add acceptance criteria checkoff to execution skills
- Add commit-and-push step to implementing-plan-phases
- Add PR creation to implementing-plan-phases
- Automate release branch creation in release script
- Add stop hook and release branch enforcement to releasing-plugins
- Add changelog noise filtering and scope collapsing
- Remove unneeded .gitkeep files

[1.4.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.3.0...lwndev-sdlc@1.4.0

## [1.3.0] - 2026-03-21

### Chores

- **documentation:** address review feedback for PR #47
- **documentation:** mark CHORE-015 as completed
- **documentation:** correct QA skill placement in workflow chains (CHORE-015)
- **documentation:** add reviewing-requirements to plugin README
- **documentation:** mark CHORE-014 as completed
- **documentation:** update README.md and CLAUDE.md for new skills (CHORE-014)
- **documentation:** update CHORE-013 status to Completed
- **refactoring:** relocate QA output paths from test/ to qa/
- **refactoring:** address PR review feedback
- **refactoring:** update CHORE-012 status to completed
- **refactoring:** flatten plugin structure, eliminate src/ and dist/
- **refactoring:** address PR review feedback
- **refactoring:** update CHORE-011 status to completed
- **refactoring:** restructure repo for multi-plugin marketplace
- **refactoring:** update repo references to lwndev-marketplace
- **refactoring:** address code review feedback
- **refactoring:** update CHORE-010 status to completed
- **refactoring:** refactor skills into Claude Code plugin structure
- **documentation:** update CHORE-009 status to completed
- **documentation:** add extend-claude-with-skills reference doc
- upgrade ai-skills-manager to 1.8.0 and update docs
- **cleanup:** remove managing-git-worktrees skill
- **refactoring:** use detailed validation in build script (#7)
- **refactoring:** expose scaffold template options (#6)
- **documentation:** add completion tracking to chore workflow (#4)
- refine gitignore patterns
- update package-lock.json peer dependency markers
- **refactoring:** align skill directory structure with spec (#3)
- **refactoring:** generalize managing-git-worktrees skill (#2)

### Bug Fixes

- **review:** address code review findings from PR #43
- **release:** address code review findings from PR #40
- **marketplace:** bump marketplace manifest version to 1.1.0
- **deps:** upgrade lodash to 4.17.23 for CVE-2025-13465
- **executing-chores:** enforce Closes #N in PR body when issue exists

### Features

- **review:** bump plugin version to 1.2.0 and complete Phase 3 verification
- **review:** add review recommendation to documenting skills (Phase 2)
- **review:** add reviewing-requirements skill and requirements (Phase 1)
- **release:** add releasing-plugins skill and update plan status (Phase 4)
- **release:** add post-merge tagging script (Phase 3)
- **release:** add release script for plugin version bumping (Phase 2)
- **release:** add shared infrastructure for plugin release workflow (Phase 1)
- **qa:** address PR review feedback
- **qa:** add executing-qa skill with multi-phase stop hook (FEAT-004 Phase 3)
- **qa:** add documenting-qa skill with stop hook and test plan template (FEAT-004 Phase 2)
- **qa:** add qa-verifier subagent and plugin infrastructure (FEAT-004 Phase 1)
- add allowed-tools declarations to all 7 skills (FEAT-003) (#20)
- add executing-bug-fixes skill (#13)
- add documenting-bugs skill (#10)

### Refactoring

- replace duplicated docs with shared ai-skills-docs submodule
- migrate scripts to ai-skills-manager v1.6.0 programmatic API

### Documentation

- fix skill count and check acceptance criteria
- add implementation notes to CHORE-007
- update CHORE-007 completion status
- update reference docs and remove date suffixes from filenames
- **implementation:** add implementation plan for documenting-bugs skill
- **requirements:** add automated test specs for documenting-bugs and executing-bug-fixes
- update README to reflect programmatic API usage
- improve implementing-plan-phases skill invocation triggers
- add filename convention to creating-implementation-plans skill
- fix ai-skills-manager repo URL in README
- update CLAUDE.md as reference implementation for ai-skills-manager
- update README as reference implementation for ai-skills-manager
- update Available Skills heading in README
