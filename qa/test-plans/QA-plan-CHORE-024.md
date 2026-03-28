# QA Test Plan: Automate Release Branch Creation

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-CHORE-024 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-024 |
| **Source Documents** | `requirements/chores/CHORE-024-release-branch-automation.md` |
| **Date Created** | 2026-03-28 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/release.test.ts` — argument validation (6 tests) | Validates CLI arg parsing, invalid bump types, missing args | PENDING |
| `scripts/__tests__/release.test.ts` — full workflow (14 tests) | Version bumping, changelog generation, README update, commit creation | PENDING |
| `scripts/__tests__/release.test.ts` — error handling (2 tests) | Dirty working tree, missing marketplace entry | PENDING |
| `scripts/__tests__/release-tag.test.ts` (6 tests) | Tag creation script — must be unaffected by branching changes | PENDING |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority |
|-----------------|----------------|-----------------|----------|
| Creates release branch when run from main | `scripts/release.ts` | AC-1 | High |
| Errors when release branch already exists | `scripts/release.ts` | AC-2 | High |
| Commits in place when not on main | `scripts/release.ts` | AC-3 | High |
| Test repos use explicit `main` branch (`git init -b main`) | `scripts/__tests__/release.test.ts` | AC-1 (prerequisite) | Medium |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| `getDefaultBranch()` fallback behavior | `scripts/lib/git-utils.ts:getDefaultBranch` | AC-1 | Verify via existing branching tests (fallback to `main` exercised in test repos without remotes) |
| `getDefaultBranch()` with remote HEAD set | `scripts/lib/git-utils.ts:getDefaultBranch` | AC-1 | Low priority — would require test repo with remote; fallback path is exercised |
| Non-"already exists" branch creation failure | `scripts/release.ts:307-319` | AC-2 | Low priority — generic error path; difficult to trigger in practice |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method |
|-------------|-------------|-------------------|-------------------|
| AC-1: Branch creation from main | Script creates `release/<plugin>-v<version>` branch when on default branch | `scripts/release.ts:302-322` — checks `currentBranch === defaultBranch`, runs `git checkout -b` | Automated test: `should create release branch when run from main` |
| AC-2: Error on existing branch | Script errors with clear message if branch already exists | `scripts/release.ts:310-319` — catches `git checkout -b` failure, inspects stderr | Automated test: `should error when release branch already exists` |
| AC-3: Commit in place on non-main | Script skips branch creation and commits on current branch | `scripts/release.ts:307` — `if` block not entered when not on default branch | Automated test: `should commit in place when not on main` |
| AC-4: Skill Phase 1 updated | Manual branch creation step removed, steps renumbered, script note added | `.claude/skills/releasing-plugins/SKILL.md` — Step 2 removed, steps 3-9 renumbered to 2-8, Step 4 notes auto-branching | Code review: verify skill diff |
| AC-5: No manual branch step | Skill no longer contains "Create a release branch" step | `.claude/skills/releasing-plugins/SKILL.md` — no `git checkout -b` in Phase 1 steps | Code review: grep for removed step |

## Deliverable Verification

| Deliverable | Description | Expected Path | Exists |
|-------------|-------------|---------------|--------|
| Updated release script | Branching logic added | `scripts/release.ts` | PENDING |
| New `getDefaultBranch()` utility | Dynamic default branch detection | `scripts/lib/git-utils.ts` | PENDING |
| Branching tests | 3 new test cases | `scripts/__tests__/release.test.ts` | PENDING |
| Updated skill | Manual step removed, steps renumbered | `.claude/skills/releasing-plugins/SKILL.md` | PENDING |
| Chore document | Completed with PR link | `requirements/chores/CHORE-024-release-branch-automation.md` | PENDING |

## Scope Verification

Changes that should NOT have been made (confirm no unrelated modifications):

| Scope Boundary | Verification |
|---------------|-------------|
| `scripts/release-tag.ts` must be unaffected | Confirm no changes to this file |
| Existing release workflow tests must pass unchanged | Confirm 22 pre-existing tests still pass |
| Stop hook in skill YAML frontmatter must be unchanged | Confirm hook prompt is identical |
| Other skill files must be unaffected | Confirm no changes outside the 4 affected files + git-utils |

## Verification Checklist

- [ ] All existing tests pass (regression baseline — 280 tests across 18 files)
- [ ] All AC entries have corresponding test plan entries
- [ ] Coverage gaps are identified with recommendations
- [ ] Code paths trace from requirements to implementation
- [ ] Deliverables are accounted for
- [ ] Scope boundaries are verified (no unrelated changes)
- [ ] New test recommendations are actionable and prioritized
