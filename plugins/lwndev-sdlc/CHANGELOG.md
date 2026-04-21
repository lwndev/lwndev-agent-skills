# Changelog

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
