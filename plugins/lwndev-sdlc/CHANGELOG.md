# Changelog

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
