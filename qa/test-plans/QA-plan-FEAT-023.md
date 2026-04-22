---
id: FEAT-023
version: 2
timestamp: 2026-04-22T03:30:00Z
persona: qa
---

## User Summary

The rollout replicates the CHORE-034 output-token-optimization pattern across twelve `lwndev-sdlc` sub-skills. Each target skill gains an `## Output Style` section (lite narration rules, load-bearing carve-outs, fork-to-orchestrator return contract), forkable skills explicitly name the contract shape they emit, main-context and cross-cutting skills note their return target, and artifact templates under `assets/` are compressed where prose-compressible. Baseline and post-change `wc` measurements are captured per skill and aggregated into a grand-total delta table in the requirements Notes section. The rollout is documentation/style only — no runtime behavior changes and `npm run validate` / `npm test` must continue to pass unchanged.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Scenarios (by dimension)

### Inputs

- [P0] A rolled-out SKILL.md has corrupted YAML frontmatter after the Output Style section insertion (missing closing `---`, mis-indented key, stray colon) | mode: test-framework | expected: vitest spec that parses every `plugins/lwndev-sdlc/skills/*/SKILL.md` via `gray-matter` or the ai-skills-manager validator and asserts frontmatter parses to a non-null object for all twelve skills.
- [P0] A target skill's `allowed-tools` list is accidentally reformatted (flow-style to block-style, or vice versa) by the edit | mode: test-framework | expected: vitest spec diffing parsed `allowed-tools` before/after to assert the set of tool names is preserved even if representation changes; pairs with a pre-rollout snapshot captured in-test fixture.
- [P1] The Output Style section is inserted with Unicode smart quotes or curly apostrophes (from a copy-paste) rather than ASCII punctuation | mode: test-framework | expected: vitest spec that greps each target SKILL.md's Output Style section for U+2018/2019/201C/201D and fails if any are present outside allowed em-dash contexts in tables.
- [P1] A skill's SKILL.md has no `## Quick Start` section — placement rule falls back to "first early-read section", and the rollout places it in an inappropriate location (e.g., inside a code block or after an existing `## Output Style`) | mode: test-framework | expected: vitest spec asserting Output Style appears exactly once per target SKILL.md and precedes at least one Step N heading.
- [P2] Baseline `wc -l -w -c` measurements captured include a non-rollout commit's changes (measurement taken after stray unrelated edits) | mode: exploratory | expected: reviewer inspects the baseline table timestamps against git log on the SKILL.md files; a stale baseline invalidates the delta.
- [P2] The Output Style section includes Unicode `→` in lite-rule text (copy-pasted from FR-14 echo spec) where ASCII `->` was required | mode: test-framework | expected: vitest spec greps the lite-narration-rules subsection for U+2192 and fails; allows Unicode `→` only under the script-emitted-log carve-out paragraph.

### State transitions

- [P0] Phase N completes with a post-change measurement; Phase N+1 or a later docs edit further modifies the same file, leaving the recorded post-change number stale | mode: exploratory | expected: reviewer verifies the Notes-section measurement table's final values against a fresh `wc` run in PR CI.
- [P0] A phase fails mid-edit (e.g., `Edit` tool on SKILL.md errors partway) and re-run applies the section twice, producing duplicate Output Style headings | mode: test-framework | expected: vitest spec asserting each target SKILL.md contains exactly one `## Output Style` heading (no duplicates) via `grep -c`.
- [P1] User resumes the workflow after a long pause; `resume-recompute` upgrades complexity from `medium` to `high`, which changes the tier for subsequent `implementing-plan-phases` forks | mode: exploratory | expected: reviewer verifies the `modelSelections` audit trail in `.sdlc/workflows/FEAT-023.json` shows the expected tier progression across all 13 phases.
- [P1] A phase is skipped (status manually flipped to `complete` without running edits) — rollout claims completion but no Output Style section exists | mode: test-framework | expected: vitest spec cross-referencing `phases.completed` count in the workflow state against the actual count of SKILL.md files containing an `## Output Style` section.
- [P2] Two concurrent Claude Code sessions resume the same workflow and try to edit the same SKILL.md — the second writer overwrites the first's partial edits | mode: exploratory | expected: reviewer checks that only one `.active` marker exists at a time and that state-file timestamps are monotonic.

### Environment

- [P1] CI runs on Linux with LF line endings while local edits land on macOS with mixed CRLF/LF — `npm run validate` passes locally but fails on CI due to line-ending diff in a rolled-out SKILL.md | mode: test-framework | expected: a GitHub Actions run in the PR executes `npm run validate` and `npm test` on linux runner; both must pass.
- [P1] Running an older Claude Code (< 2.1.72) on the rolled-out skills triggers the NFR-6 fallback path — fork subagents inherit parent tier instead of receiving the computed one | mode: exploratory | expected: reviewer verifies that the `[model] Agent tool rejected model parameter` warning appears and the audit trail still records the intended tier for each fork.
- [P1] A contributor on Windows checks out the branch and `npm run validate` mangles relative paths in references (backslash vs forward slash) | mode: exploratory | expected: reviewer runs `git config core.autocrlf` inspection; the validate script should accept POSIX paths regardless of platform.
- [P2] Disk fills between baseline and post-change measurement — post-change `wc` fails silently, leaving the Notes table with `N/A` rows | mode: exploratory | expected: reviewer inspects the Notes table for missing rows; a fresh measurement run on clean disk confirms completeness.
- [P2] Running `find` / `wc` in a directory with a stray `node_modules` under a skill's `references/` folder inflates measurements by thousands of lines | mode: test-framework | expected: vitest spec greps the Notes-section measurement table for any file path under `node_modules/` and fails if present.

### Dependency failure

- [P0] The `ai-skills-manager` validator (`validate()` API used by `npm run validate`) rejects a rolled-out SKILL.md because a new heading or YAML shape triggers a schema check we did not anticipate | mode: test-framework | expected: vitest spec calling `validate()` against every target skill and asserting `result.ok === true` for all twelve after the rollout is complete.
- [P1] A pre-existing test asserts on narration text that the rollout trimmed (e.g., a status-echo line removed from a SKILL.md procedure section), causing a test regression | mode: test-framework | expected: `npm test` passes end-to-end after the final phase; any trimmed-narration test is updated in the same PR and called out in the body.
- [P1] The `prepare-fork.sh` script reads the target skill's SKILL.md during fork ceremony and the new Output Style section introduces a heading that a downstream parser (not the validator) misinterprets as a section boundary | mode: exploratory | expected: reviewer runs one full feature-chain workflow against a canned fixture after phase N lands and confirms forks still resolve correctly.
- [P1] `gh pr view` in CI-reconciliation mode of `reviewing-requirements` depends on PR metadata shape; rolled-out changes to that skill's internal steps accidentally break the mode-detection precedence (PR takes precedence over test plan) | mode: test-framework | expected: vitest spec that mocks `gh pr view` and `Glob` for the test plan, invokes the resolved reviewing-requirements skill end-to-end, and asserts code-review mode is entered when both signals are present.
- [P2] A third-party markdown renderer (GitHub web UI, VS Code preview) renders the Output Style section's carve-out bullets differently because of mixed indentation introduced during the rollout | mode: exploratory | expected: reviewer opens three representative skill SKILL.md files in the GitHub web preview and confirms the Output Style section renders cleanly with no broken lists.

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P1] Cross-skill consistency fails: the lite-rule wording or carve-out list drifts across the twelve rolled-out skills, violating the NFR for canonical wording | mode: test-framework | expected: vitest spec that extracts the Output Style section body from each target SKILL.md, hashes the lite-rules and carve-outs subsections, and asserts the hash is identical across all twelve (or that documented per-skill deviations are enumerated in a known allowlist fixture).
- [P1] Permissions: a target skill's `allowed-tools` does not include `Bash` / `Edit` / `Read` that the Output Style section's procedural prose implies it can invoke (e.g., the section references `fail` calls but the skill has no way to invoke them) | mode: test-framework | expected: vitest spec cross-referencing each target skill's `allowed-tools` against the set of tool names implied by its Output Style section.
- [P1] The rolled-out Output Style section on `managing-work-items` incorrectly describes its contract as forked-return when the skill is cross-cutting / inline — leading future authors to emit `done | ...` tokens from an inline call site | mode: test-framework | expected: vitest spec asserting `managing-work-items`'s Output Style Fork-to-orchestrator subsection contains the substring "inline" and does not say the skill emits `done | artifact=`.
- [P2] I18n: a non-ASCII SKILL.md contributor pastes Japanese or Arabic content into a rolled-out Output Style section during a subsequent PR, and the section-placement regex used by future tests breaks on non-ASCII headings | mode: exploratory | expected: reviewer forward-tests the grep regex used in the placement-assertion test against a SKILL.md whose Output Style section contains non-ASCII prose in one bullet.
- [P2] Concurrency: the `measurement` commands in the final grand-total phase race with active edits if a developer is hand-editing a SKILL.md during the run — final table numbers are off-by-one | mode: exploratory | expected: reviewer ensures the grand-total phase runs on a clean working tree (`git status` shows no unstaged changes before `wc` is invoked).
- [P2] a11y is non-applicable for a CLI-only documentation rollout — but a screen-reader rendering of the rolled-out Output Style bullet list (via VS Code accessibility preview) still flags nested bullets with confusing depth cues | mode: exploratory | expected: reviewer opens one rolled-out SKILL.md in VS Code's accessibility preview mode; bullet depth must be coherent.

## Non-applicable dimensions

- (none) — every adversarial dimension applies to this rollout because it touches twelve separate SKILL.md files (Inputs: YAML/frontmatter surface), moves through a 13-phase state machine (State transitions), runs across platforms and Claude Code versions (Environment), depends on `ai-skills-manager` and vitest (Dependency failure), and must preserve cross-skill consistency, permissions, and rendering correctness (Cross-cutting). The `a11y` sub-dimension of Cross-cutting is mostly inapplicable to a docs-only change but is probed via one exploratory scenario for completeness.
