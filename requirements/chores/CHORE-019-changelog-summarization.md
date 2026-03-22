# Chore: Changelog Summarization

## Chore ID

`CHORE-019`

## GitHub Issue

[#59](https://github.com/lwndev/lwndev-marketplace/issues/59)

## Category

`refactoring`

## Description

Refactor changelog generation in the release script to produce concise, user-facing summaries instead of one bullet per commit. The current approach dumps every commit verbatim, resulting in noisy changelogs filled with entries like "address review feedback" and "mark CHORE-015 as completed" that provide no value to users.

## Affected Files

- `scripts/release.ts` — added `collapseByScope()` (lines 151–185), modified `generateChangelog()` to call `filterNoiseCommits` and `collapseByScope` (lines 187–221)
- `scripts/lib/git-utils.ts` — added `NOISE_PATTERNS` and `filterNoiseCommits()` (lines 89–98)
- `.claude/skills/releasing-plugins/SKILL.md` — added Step 6 "Refine the changelog", renumbered subsequent steps
- `scripts/__tests__/git-utils.test.ts` — new unit tests for `filterNoiseCommits` (8 tests)
- `scripts/__tests__/release.test.ts` — added 5 integration tests for noise filtering, scope collapsing, and edge cases

## Acceptance Criteria

### Script-level (`scripts/release.ts`, `scripts/lib/git-utils.ts`)
- [x] Noise commits are filtered out before changelog generation (e.g., "address review feedback", "mark * as completed", "update * status", merge commits)
- [x] Related commits are collapsed by scope/feature into single descriptive entries
- [x] `generateChangelog()` produces a concise, user-facing summary rather than one bullet per commit
- [x] The release script (`npm run release`) continues to run non-interactively
- [x] New tests cover the filtering and collapsing logic

### Skill-level (`.claude/skills/releasing-plugins/SKILL.md`)
- [x] The releasing-plugins skill workflow integrates summarization (either as a pre-step before the script or a post-step edit of the generated changelog)

### General
- [x] Existing tests pass after changes

## Completion

**Status:** `Completed`

**Completed:** 2026-03-22

**Pull Request:** [#61](https://github.com/lwndev/lwndev-marketplace/pull/61)

## Notes

- The release script runs non-interactively and commits automatically, so any AI-assisted summarization must happen in the skill workflow (before or after the script), not within the script itself.
- Summarization was added as Step 6 "Refine the changelog" in SKILL.md, before the review step (now Step 7). The skill reviews and optionally rewrites the auto-generated changelog before the release commit is finalized.
- Hybrid approach implemented: script-level filtering of noise commits + scope collapsing at the script level, with skill-level refinement for wording and cross-scope consolidation.
