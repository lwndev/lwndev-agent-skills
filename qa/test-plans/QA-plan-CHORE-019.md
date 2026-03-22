# QA Test Plan: Changelog Summarization

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-CHORE-019 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-019 |
| **Source Documents** | `requirements/chores/CHORE-019-changelog-summarization.md` |
| **Date Created** | 2026-03-22 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/release.test.ts` | Release script argument validation, full workflow (version bumping, changelog generation, marketplace sync), error handling | PENDING |
| `scripts/__tests__/release-tag.test.ts` | Release tagging (branch checks, dirty tree, tag creation) | PENDING |

Key existing assertions that exercise changelog generation:
- `release.test.ts:176-179` — verifies changelog contains version header and commit entries (`### Bug Fixes`, `fix a bug`)
- `release.test.ts:256-277` — verifies commits are grouped by conventional type (`### Features`, `### Bug Fixes`, `### Documentation`) with scope prefixes
- `release.test.ts:279-298` — verifies new versions prepend to existing changelog

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority |
|-----------------|----------------|-----------------|----------|
| Noise commits (e.g., "address review feedback", "mark X as completed") are excluded from changelog output | `scripts/release.ts`, `scripts/lib/git-utils.ts` | AC: noise filtering | High |
| Merge commits are excluded from changelog output | `scripts/release.ts`, `scripts/lib/git-utils.ts` | AC: noise filtering | High |
| Commits with the same scope are collapsed into a single entry | `scripts/release.ts` | AC: collapsing by scope | High |
| Collapsed entries produce a meaningful description (not just the first commit message) | `scripts/release.ts` | AC: concise summary | Medium |
| Non-noise commits still appear in changelog (no over-filtering) | `scripts/release.ts` | AC: concise summary | High |
| Release script runs without interactive prompts after changes | `scripts/release.ts` | AC: non-interactive | Medium |
| Existing grouped-by-type changelog format is preserved (headers like `### Features`, `### Bug Fixes`) | `scripts/release.ts` | AC: concise summary | Medium |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| No test for filtering logic (noise patterns) | `scripts/release.ts` or `scripts/lib/git-utils.ts` (new filter function) | AC: noise filtering | Write unit tests with known noise commit messages and verify they are excluded |
| No test for collapsing logic (same-scope grouping) | `scripts/release.ts` (modified `groupCommitsByType` or new function) | AC: collapsing by scope | Write unit tests with multiple commits sharing a scope and verify single output entry |
| No test for edge case: all commits are noise | `scripts/release.ts:generateChangelog` | AC: concise summary | Write unit test verifying graceful output (e.g., "No notable changes.") |
| No test for edge case: single meaningful commit (nothing to collapse) | `scripts/release.ts:generateChangelog` | AC: collapsing by scope | Write unit test verifying single commit passes through unchanged |
| Skill workflow summarization step not testable via automated tests | `.claude/skills/releasing-plugins/SKILL.md` | AC: skill integration | Manual verification via code review |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method |
|-------------|-------------|-------------------|-------------------|
| AC: Noise commits filtered | Commits matching noise patterns (e.g., "address review feedback", "mark * as completed", merge commits) are removed before changelog generation | `scripts/lib/git-utils.ts:getCommitsSinceTag` or new filter in `scripts/release.ts` | Automated test |
| AC: Collapsed by scope | Commits sharing the same scope/feature are merged into a single changelog entry | `scripts/release.ts:groupCommitsByType` or new collapsing function | Automated test |
| AC: Concise summary | `generateChangelog()` output is shorter and more meaningful than one-bullet-per-commit | `scripts/release.ts:generateChangelog` | Automated test + manual review of sample output |
| AC: Non-interactive | Release script accepts no interactive prompts | `scripts/release.ts` (main function) | Automated test (existing tests already verify this via `execSync` with piped stdio) |
| AC: New tests | Tests exist for filtering and collapsing logic | `scripts/__tests__/release.test.ts` | Code review — verify new test cases exist |
| AC: Skill integration | Releasing-plugins skill includes a summarization step | `.claude/skills/releasing-plugins/SKILL.md` | Code review — verify new/modified step in skill instructions |
| AC: Existing tests pass | All existing tests in the test suite continue to pass | All `scripts/__tests__/*.test.ts` | `npm test` |

## Deliverable Verification

| Deliverable | Source | Expected Path | Exists |
|-------------|--------|---------------|--------|
| Modified changelog generation logic | Script-level ACs | `scripts/release.ts` | PENDING |
| Modified or extended commit retrieval/filtering | Script-level ACs | `scripts/lib/git-utils.ts` | PENDING |
| Updated skill workflow with summarization step | Skill-level AC | `.claude/skills/releasing-plugins/SKILL.md` | PENDING |
| New/updated tests for filtering and collapsing | Script-level ACs | `scripts/__tests__/release.test.ts` | PENDING |

## Verification Checklist

- [ ] All existing tests pass (regression baseline)
- [ ] All AC entries have corresponding test plan entries
- [ ] Coverage gaps are identified with recommendations
- [ ] Code paths trace from requirements to implementation
- [ ] Deliverables are accounted for
- [ ] New test recommendations are actionable and prioritized
