# QA Test Plan: Tighten Bug Classifier and Skip Unnecessary Fork Steps

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-CHORE-031 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-031 |
| **Source Documents** | `requirements/chores/CHORE-031-tighten-classifier-skip-steps.md` |
| **Date Created** | 2026-04-12 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/workflow-state.test.ts` — `bug classifier` suite | 7 tests covering `_classify_bug` across severity/RC/category combinations | PASS |
| `scripts/__tests__/orchestrating-workflows.test.ts` — `${CLAUDE_SKILL_DIR}` ref count | Asserts all `workflow-state.sh` references use the prefixed form (count = 66) | PASS |
| `scripts/__tests__/orchestrating-workflows.test.ts` — chore chain lifecycle | Full 9-step chore chain init → advance → pause → resume → complete | PASS |
| `scripts/__tests__/orchestrating-workflows.test.ts` — bug chain lifecycle | Full 9-step bug chain init → advance → pause → resume → complete | PASS |
| `scripts/__tests__/orchestrating-workflows.test.ts` — FEAT-014 adaptive model selection | Examples A, B, C verifying tier resolution across chain types | PASS |
| `scripts/__tests__/workflow-state.test.ts` — feature init classifier | 6 tests ensuring feature classifier is unaffected | PASS |
| `scripts/__tests__/workflow-state.test.ts` — chore classifier | 6 tests ensuring chore classifier is unaffected | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| Critical severity alone caps at medium | `workflow-state.test.ts` — `bug-critical-severity.md` fixture | AC-1 | High | PASS |
| RC count 4 alone caps at medium when severity is low | `workflow-state.test.ts` — `bug-max-severity-rc.md` fixture | AC-1 | High | PASS |
| High severity + 4 RCs + logic-error → high via rc_tier branch | `workflow-state.test.ts` — `bug-high-rc-only.md` fixture | AC-1, AC-2 | High | PASS |
| High severity + 3 RCs + security category → high (unchanged) | `workflow-state.test.ts` — `bug-high.md` fixture | AC-5 | Medium | PASS |
| `${CLAUDE_SKILL_DIR}` reference count updated to 66 | `orchestrating-workflows.test.ts` line 70 | AC-3, AC-4 | Medium | PASS |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| No automated test for step 2/4 skip behavior at runtime | `SKILL.md` step 2/4 skip conditions (prose instructions) | AC-3, AC-4 | Manual verify: inspect SKILL.md prose for correct skip conditions and `advance` calls |
| No automated test for `severity=medium + rc_count>=4 + logic-error` | `workflow-state.sh:_classify_bug` | AC-1 | Manual verify: trace through logic to confirm this returns `high` |
| Feature chain step tables have no skip annotations | `SKILL.md` feature chain step sequence | AC-5 | Manual verify: confirm feature chain tables at lines 198-211 are untouched |

## Code Path Verification

Traceability from acceptance criteria to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| AC-1 | `_classify_bug` no longer returns `high` from severity alone or RC count alone | `workflow-state.sh:531-540` — T1 guard caps `base` at `medium` when `sev_rank < 2` or no escalation signal | Automated: 3 tests (`bug-critical-severity`, `bug-max-severity-rc`, `bug-high-rc-only`) | PASS |
| AC-2 | A BUG-009-equivalent bug resolves to `sonnet` | `workflow-state.sh:534-539` — severity=high + 1 RC + documentation → `sev_rank=3` but `rc_tier != "high"` and `cat_bump != "true"` → capped to `medium` (sonnet) | Automated: `bug-critical-severity` test (severity=critical, 1 RC, logic-error → medium) | PASS |
| AC-3 | Bug/chore chains with `complexity == low` skip step 2 | `SKILL.md:637-641` (chore) and `SKILL.md:688-692` (bug) — skip condition reads complexity from state file, calls `advance` if low | Manual: inspect SKILL.md prose, confirm `advance` call, confirm step tables annotated | PASS |
| AC-4 | Test-plan reconciliation fork skipped when `complexity == low` | `SKILL.md:643-647` (chore) and `SKILL.md:694-698` (bug) — skip condition gates on `complexity == low` only | Manual: inspect SKILL.md prose, confirm `advance` call, confirm step tables annotated | PASS |
| AC-5 | Feature-chain behavior unchanged | Feature chain step table (`SKILL.md:198-211`), feature chain fork instructions (`SKILL.md:607-632`) | Manual: confirm no CHORE-031 annotations in feature chain sections; automated: feature classifier tests unchanged | PASS |

## Deliverable Verification

| Deliverable | Source | Expected Path | Status |
|-------------|--------|---------------|--------|
| Refactored `_classify_bug` with T1 guard | T1 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh:531-540` | PASS |
| Step 2 skip condition in chore chain fork instructions | T2 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:637-641` | PASS |
| Step 2 skip condition in bug chain fork instructions | T2 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:688-692` | PASS |
| Step 4 skip condition in chore chain fork instructions | T6 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:643-647` | PASS |
| Step 4 skip condition in bug chain fork instructions | T6 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:694-698` | PASS |
| Step table annotations (chore chain) | T2, T6 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:220,222` | PASS |
| Step table annotations (bug chain) | T2, T6 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:236,238` | PASS |
| Updated verification checklist | Review fix | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:992` | PASS |
| Updated "every fork" preamble (chore chain) | Review fix | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:635` | PASS |
| Updated "every fork" preamble (bug chain) | Review fix | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:686` | PASS |
| New test fixture `bug-high-rc-only.md` | Review fix | `scripts/__tests__/fixtures/feat-014/bug-high-rc-only.md` | PASS |
| Chore document | CHORE-031 | `requirements/chores/CHORE-031-tighten-classifier-skip-steps.md` | PASS |
| Vitest worktree exclusion | Bonus fix | `vitest.config.ts:6` | PASS |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
