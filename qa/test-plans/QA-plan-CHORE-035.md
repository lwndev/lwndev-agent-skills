---
id: CHORE-035
version: 2
timestamp: 2026-04-21T18:36:48Z
persona: qa
---

## User Summary

Reduce input tokens consumed by the `orchestrating-workflows` skill's instruction surface — the static SKILL.md text loaded on every orchestrator invocation and every forked sub-agent spawn — by compressing prose to *lite* style, relocating heavy narrative sections into `references/` so SKILL.md reads as a thin dispatcher, and collapsing the three per-chain step-sequence tables (feature / chore / bug) into one parameterized table plus a per-chain deltas note. The pilot captures before/after measurements and learnings, then files a follow-up rollout issue for the remaining twelve `lwndev-sdlc` skills. Scope is deliberately limited to `orchestrating-workflows/SKILL.md` and its `references/*.md` so a pilot-sized experiment can inform the larger rollout. The Output Style directive and fork-return contract installed by CHORE-034 must be preserved verbatim.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Scenarios (by dimension)

### Inputs

- [P0] Relocated section's original inline anchor is referenced elsewhere (another skill, another reference file, a test) and that link breaks after relocation | mode: test-framework | expected: `npm run validate` catches broken inline anchor/link resolution, or an explicit anchor-resolution test asserts that every anchor referenced from any `plugins/lwndev-sdlc/**/*.md` file still resolves
- [P0] Prose compression accidentally modifies a code block, command line, flag, file path, step-name token, or table header that `workflow-state.sh` / `prepare-fork.sh` / downstream parsers rely on | mode: test-framework | expected: vitest suite still passes; specifically the bats / shell-script assertion tests that pin the exact step-name strings, tier tokens, and log formats emitted by the shell scripts
- [P0] Consolidated parameterized chain-step table loses a row/column that was present in one of the three original tables (e.g., the feature chain's phase-loop deltas, or the chore-chain's step-2 skip condition annotation) | mode: test-framework | expected: a structural assertion or manual diff check confirms every row of the three original tables maps to a row in the consolidated table plus deltas note; no step is silently dropped
- [P1] Pronoun drops during prose compression create ambiguous antecedents (e.g., "It may downgrade below baseline" — what does "it" refer to after the subject sentence was tightened?) | mode: exploratory | expected: a human reader of the post-change SKILL.md can parse every pronoun without re-reading the surrounding paragraph
- [P1] Relocated section lands in the wrong reference file (e.g., step-execution detail moved into `chain-procedures.md`), weakening the thin-dispatcher intent | mode: exploratory | expected: each relocated section is placed in the reference file whose topic matches it; the inline pointer identifies the correct target
- [P1] Reference-file inline pointer from SKILL.md is stale (points to a heading that has been renamed or split during relocation) | mode: test-framework | expected: every inline pointer in SKILL.md resolves to a heading or section that exists in the target reference file
- [P2] Deltas note after the consolidated chain-step table contradicts a row in the table itself (e.g., the note claims a feature chain has 5 pause points but the unified table shows 2 for feature) | mode: exploratory | expected: spot-check that the note only describes differences and every claim in the note agrees with the table
- [P2] Measurement-table mathematics are wrong (pre/post delta numbers do not arithmetically match the individual file counts) | mode: exploratory | expected: baseline/post-change/delta tables are internally consistent; totals match the sum of per-file rows

### State transitions

- [P0] An in-flight workflow state file (written before CHORE-035 lands) is resumed after the pilot merges — SKILL.md's step sequence has been reorganized into a parameterized table but the step-index numbering must not shift | mode: test-framework | expected: existing `.sdlc/workflows/*.json` state files still resume correctly; step-index values persisted before the chore match the same logical step after the chore
- [P1] A workflow is paused mid-resume while the user is upgrading the plugin version, so the pre-upgrade SKILL.md wrote a state file that the post-upgrade SKILL.md must read | mode: exploratory | expected: state-file schema is unchanged; no behavioral reliance on specific SKILL.md line/section ordering
- [P1] Relocated content's cross-skill references (e.g., from `reviewing-requirements/SKILL.md` to an anchor in `orchestrating-workflows/SKILL.md`) survive the relocation | mode: test-framework | expected: all inbound links from other skills still resolve to a reachable section (either the same anchor in SKILL.md, or an equivalent anchor in the reference file the content moved to)
- [P2] Partial PR merge scenario — the chore branch updates SKILL.md but a reference file's companion edit is missing from the PR | mode: exploratory | expected: reviewer catches via `npm run validate` plus manual pointer-resolution check; no one-sided edits escape review

### Environment

- [P0] Existing vitest suite passes (`npm test`) after the edits land | mode: test-framework | expected: zero test failures introduced by the SKILL.md + references edits
- [P0] `npm run validate` still passes after the edits land (frontmatter + skill structure still valid) | mode: test-framework | expected: SKILL.md frontmatter remains well-formed; reference-file links resolve; no broken plugin structure
- [P0] Orchestrator behavior is unchanged end-to-end for a reference workflow run on both sides of the merge | mode: exploratory | expected: a reference feature and a reference chore workflow both advance through every step with equivalent artifacts and prompts, before and after the chore — the optimization is content-neutral
- [P1] Measurement reproducibility — the input-token estimator produces consistent counts across two runs of the same file | mode: exploratory | expected: measurement variance is documented in the baseline table; the pilot does not claim savings inside the noise floor of the chosen estimator
- [P1] Anthropic `/v1/messages/count_tokens` endpoint unavailable during measurement collection (network down, auth issue) — fallback BPE estimator activates | mode: exploratory | expected: whichever estimator is used is recorded in the Baseline Measurements subsection; both baseline and post measurements use the same estimator
- [P2] Skill under a non-default plugin-cache path (`CLAUDE_PLUGIN_ROOT` override) — SKILL.md resolution and reference-file reads still work | mode: exploratory | expected: absolute paths in SKILL.md still resolve; no regressions from the relocations
- [P2] Markdown-renderer differences (GitHub vs. VS Code preview vs. Claude Code in-terminal rendering) — consolidated table renders correctly in every surface | mode: exploratory | expected: no column alignment or escape-character regressions; the parameterized table is legible in every renderer the team uses

### Dependency failure

- [P1] `gh` CLI unavailable or unauthenticated during the reference workflow run used for measurement | mode: exploratory | expected: measurement still completes against the local file system; baseline/post numbers remain comparable because both runs face the same environment
- [P1] Capability discovery, persona loader, or `prepare-fork.sh` scripts still locate their inputs after SKILL.md prose is compressed — no script relies on a specific string existing in SKILL.md beyond the documented frontmatter | mode: test-framework | expected: scripts in `plugins/lwndev-sdlc/skills/*/scripts/*.sh` pass their existing bats tests without modification
- [P2] A sub-skill SKILL.md referenced by the orchestrator (e.g., `reviewing-requirements/SKILL.md`, `documenting-qa/SKILL.md`) is unreadable during a pilot-measurement reference run | mode: exploratory | expected: existing `prepare-fork.sh` SKILL.md-readability check fires and the orchestrator fails fast — behavior unchanged by this chore

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] Load-bearing carve-out regression — prose compression strips one of the documented carve-outs (error messages from `fail`, security warnings, interactive prompts, findings display from `reviewing-requirements`, FR-14 echoes, tagged structured logs `[info]`/`[warn]`/`[model]`, user-visible state transitions) | mode: exploratory | expected: post-change SKILL.md still lists every carve-out verbatim in the Output Style section; a reference workflow visibly emits each carve-out category
- [P0] Output Style section installed by CHORE-034 is preserved verbatim — the lite-rule bullet list, the load-bearing carve-outs list, and the fork-to-orchestrator return contract subsection all survive the relocation | mode: test-framework | expected: a structural test or manual diff confirms the Output Style section text matches the CHORE-034 baseline (no deletions, no weakening rewrites)
- [P0] Fork-return contract invariants are preserved: three canonical shapes (`done | artifact=<path> | <note>`, `failed | <reason>`, `Found **N errors**, **N warnings**, **N info**` for reviewing-requirements) remain explicitly named; precedence sentence still says the contract beats lite rules | mode: exploratory | expected: every fork invocation in SKILL.md and `references/step-execution-details.md` still references the canonical shape
- [P1] Rollout scope drift — a reviewer mistakenly applies the pilot prose-compression edits to sub-skill SKILL.md files (out of pilot scope) | mode: exploratory | expected: pilot-scope section of the chore doc plus acceptance criteria are unambiguous; PR diff shows only the three in-scope files changed (plus measurement/learning appends to the chore doc itself)
- [P1] Follow-up rollout issue is filed but does not cross-link CHORE-035, the learnings subsection, or the sibling CHORE-034 rollout issue #200 | mode: exploratory | expected: the follow-up issue body references this chore, the learnings subsection, and is cross-linked bidirectionally with issue #200 so future-us can find the full picture
- [P1] Consolidated chain-step table is over-parameterized to the point of reducing readability — a reader of SKILL.md cannot quickly see what a chore chain looks like versus a feature chain | mode: exploratory | expected: human reader can reconstruct each per-chain step sequence from the unified table plus deltas note in under 30 seconds of reading
- [P2] Permissions — none of the edits require new permissions in `settings.json` | mode: exploratory | expected: no `settings.json` / `.claude/settings.local.json` changes are required by this chore

## Non-applicable dimensions

- Inputs (injection attacks): this chore edits markdown documentation consumed by the LLM, not user-facing input surfaces. SQL/XSS/command-injection vectors do not apply to a prompt-optimization pass.
- State transitions (browser navigation, back/forward): no UI surface exists for this chore.
- Environment (offline / slow network in normal operation): SKILL.md and its reference files are local markdown; the orchestrator reads them locally. Network quality matters only for the measurement step, covered under Environment and Dependency failure rows above.
- Dependency failure (third-party API 5xx, queue overflow, database disconnect): the chore adds no new runtime dependencies. Only the measurement step and reference-workflow runs touch external services (`gh`), covered above.
- Cross-cutting (a11y, i18n screen readers, RTL layout): the orchestrator has no rendered UI. Accessibility and visual i18n are not applicable to a prompt-optimization pass targeting an instruction-surface file.
