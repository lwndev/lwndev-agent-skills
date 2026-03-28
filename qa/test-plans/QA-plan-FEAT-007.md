# QA Test Plan: Code-Review Reconciliation Mode for Reviewing Requirements

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-FEAT-007 |
| **Requirement Type** | FEAT |
| **Requirement ID** | FEAT-007 |
| **Source Documents** | `requirements/features/FEAT-007-code-review-reconciliation-mode.md`, `requirements/implementation/FEAT-007-code-review-reconciliation-mode.md` |
| **Date Created** | 2026-03-28 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/build.test.ts` | Validates all skills pass `ai-skills-manager` validation; confirms `reviewing-requirements` skill exists in the skills directory (line 81) | PENDING |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| # | Test Description | Target File(s) | Requirement Ref | Priority |
|---|-----------------|----------------|-----------------|----------|
| 1 | SKILL.md frontmatter includes all three modes in description | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-8, AC-9, Phase 1 Step 5 | High |
| 2 | SKILL.md documents code-review reconciliation mode steps (CR1-CR5) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-8, AC-7, Phase 2 Step 1 | High |
| 3 | SKILL.md contains PR detection logic (branch naming patterns `feat/{ID}-*`, `chore/{ID}-*`, `fix/{ID}-*`) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-1, AC-1, Phase 1 Step 6 | High |
| 4 | SKILL.md contains mode detection table with all three modes and their triggers | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-6, AC-10, Phase 1 Step 6 | High |
| 5 | SKILL.md "Relationship to Other Skills" section includes code-review reconciliation workflow position and `executing-qa` boundary | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-8, AC-7, Phase 2 Step 5 | High |
| 6 | SKILL.md verification checklist includes code-review reconciliation items (PR detected, test plan compared, issue suggestions, drift summary, scope boundary, severity) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-8, Phase 2 Step 4 | Medium |
| 7 | SKILL.md token count is under ~6500 tokens after all additions | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-8, AC-11, Phase 1 Step 7, Phase 2 Step 7 | Medium |
| 8 | SKILL.md standard review steps (1-9) preserve all behavioral checks — every check type and classification rule present in the pre-implementation version is still present (may be condensed) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-6, AC-6, Phase 1 Step 2 | High |
| 9 | SKILL.md test-plan reconciliation steps (R1-R7) preserve all behavioral checks — every check type and classification rule present in the pre-implementation version is still present (may be condensed) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-6, AC-6, Phase 1 Step 3 | High |
| 10 | SKILL.md severity classification (Error/Warning/Info) is documented for code-review reconciliation findings using the same conventions as other modes | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-7, AC-8, Phase 2 Step 3 | Medium |
| 11 | SKILL.md documents three finding categories: Test Plan Staleness, GitHub Issue Suggestions, Requirements ↔ Code Drift | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-7, Phase 2 Step 3 | Medium |
| 12 | SKILL.md documents scope boundary with `executing-qa` (advisory only, no affected files updates, no implementation plan modifications, no deviation summaries, no auto-fixes) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-5, AC-5, Phase 2 Step 2 | High |
| 13 | SKILL.md documents `--pr` flag support for user-provided PR number | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-1, AC-1, Phase 1 Step 6 | Medium |
| 14 | SKILL.md documents draft PR handling in mode display (`found Draft PR #N`) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-1, Phase 1 Step 6 | Low |
| 15 | SKILL.md documents multiple PR match handling (most recently updated open PR, or ask user) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-1, Phase 1 Step 6 | Low |
| 16 | SKILL.md documents `git diff <base-branch>...HEAD` fallback when `gh` is unavailable | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-4, NFR-2, Phase 2 Step 1 (CR1) | Medium |
| 17 | SKILL.md documents large PR diff warning (> 100 changed files) and focus-on-relevant-files instruction | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | NFR-1, EC-5 | Low |
| 18 | SKILL.md notes fork PR compatibility (`gh pr diff` works for fork PRs) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | EC-8 | Low |
| 19 | SKILL.md documents invalid `--pr` value handling (error and fall back to branch-based detection) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-1, EC-9, Phase 1 Step 6 | Low |
| 20 | SKILL.md documents code-review reconciliation precedence over test-plan reconciliation when both PR and test plan exist | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-1, AC-10, Phase 1 Step 6 | Medium |
| 21 | Document Type Adaptations section condensed or removed per token budget strategy (Phase 1 Step 4) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-8, AC-11, Phase 1 Step 4 | Medium |
| 22 | SKILL.md documents branch naming non-conformance fallthrough ("No PR detected via branch naming convention. Use `--pr <number>` to specify a PR.") | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-1, EC-7, Phase 1 Step 6 | Low |
| 23 | SKILL.md documents skip behavior when requirement has no GitHub Issue field (skip CR3, note as Info) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-3, NFR-2, EC-6, Phase 2 Step 1 | Low |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| # | Gap Description | Affected Code | Requirement Ref | Recommendation |
|---|----------------|---------------|-----------------|----------------|
| 1 | No dedicated test file exists for `reviewing-requirements` skill | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-6 | Write `scripts/__tests__/reviewing-requirements.test.ts` following the established pattern (SKILL.md validation, allowed-tools validation, asset validation, API validation) |
| 2 | Runtime behavior of code-review reconciliation mode is not unit-testable (prompt-based skill) | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-1 through FR-7 | Manual verification — invoke `/reviewing-requirements` against a real PR and verify output matches expected categories and format |
| 3 | Test plan drift detection accuracy (FR-2) requires a real PR diff to verify | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-2, AC-2 | Manual verification — run against a PR with known changed function signatures and verify flagged entries are accurate |
| 4 | GitHub issue suggestion quality (FR-3) requires real issue context to verify | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-3, AC-3 | Manual verification — run against a PR with scope changes from its linked issue and verify suggestions are relevant |
| 5 | Mode detection precedence (code-review reconciliation over test-plan reconciliation) is not unit-testable | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-1, AC-10 | Manual verification — invoke with a requirement ID that has both a test plan and a PR, confirm code-review reconciliation mode is selected |
| 6 | Token budget trimming verification requires before/after comparison | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | FR-6, AC-6, Phase 1 | Code review via git diff of SKILL.md before and after Phase 1 �� verify every check type in Steps 3-7 and R1-R7 is preserved |

## Code Path Verification

Traceability from requirements to implementation plan:

| Requirement | Description | Expected Code Path | Impl Phase | Verification Method |
|-------------|-------------|-------------------|------------|-------------------|
| FR-1 | PR detection and mode entry via branch naming or `--pr` flag | `SKILL.md` Step 1.5: extend with `gh pr list --head <branch-pattern>`, `gh pr view <number>`, precedence rule, draft/multi-PR handling | Phase 1 Step 6 | Code review + manual invocation |
| FR-2 | Test plan ↔ code drift detection | `SKILL.md` Step CR2: load test plan, fetch PR diff via `gh pr diff`, compare Code Path Verification / New Test Analysis / Coverage Gap Analysis entries against diff | Phase 2 Step 1 | Code review + manual invocation |
| FR-3 | GitHub issue update suggestions | `SKILL.md` Step CR3: compare PR diff and requirements against linked GitHub issue, produce draft suggestions for scope changes, decisions, deferred work | Phase 2 Step 1 | Code review + manual invocation |
| FR-4 | Advisory requirements ↔ code drift summary | `SKILL.md` Step CR4: compare PR diff against FR-N entries, acceptance criteria, edge cases; fall back to `git diff <base-branch>...HEAD` if `gh` unavailable | Phase 2 Step 1 | Code review + manual invocation |
| FR-5 | Scope boundary enforcement | `SKILL.md` code-review reconciliation section: explicit callout — no affected files updates, no implementation plan modifications, no deviation summaries, no auto-fixes | Phase 2 Step 2 | Code review |
| FR-6 | Existing mode preservation | `SKILL.md` Steps 1-9 and R1-R7: behavioral semantics preserved through condensing; verified via git diff before/after Phase 1 | Phase 1 Steps 2-4 | Code review (git diff) |
| FR-7 | Findings presentation with severity classification and three categories | `SKILL.md` code-review reconciliation findings subsection: category grouping, severity identifiers, summary format | Phase 2 Step 3 | Code review + manual invocation |
| FR-8 | SKILL.md updates (frontmatter, mode table, workflow section, verification checklist, token budget) | `SKILL.md` frontmatter, Step 1.5, Verification Checklist, Relationship to Other Skills | Phase 1 Step 5-6, Phase 2 Steps 4-5 | Code review + automated validation |
| NFR-1 | Performance — complete analysis within a single interaction for typical PRs (< 50 changed files) | Runtime behavior; large PR (> 100 files) warning documented | Phase 2 | Manual verification |
| NFR-2 | Error handling — graceful degradation when `gh` unavailable, PR closed/merged, no test plan, inaccessible issue | `SKILL.md` CR1: `git diff` fallback; CR2: skip if no test plan; CR3: skip if no issue | Phase 2 Step 1 | Code review + manual edge case testing |
| NFR-3 | Non-destructive — no documents modified, no GitHub issues posted | `SKILL.md` code-review reconciliation section: explicitly advisory, scope boundary note | Phase 2 Step 2 | Code review |

## Deliverable Verification

Implementation plan: `requirements/implementation/FEAT-007-code-review-reconciliation-mode.md` (2 phases).

### Phase 1 Deliverables

| # | Deliverable | Impl Step | Expected Path | NTA/CPV Trace | Exists |
|---|-------------|-----------|---------------|---------------|--------|
| 1 | Trimmed SKILL.md content (~1300-2000 tokens saved from Steps 3-7, R1-R7, Document Type Adaptations) | Steps 2-4 | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | NTA 8/9/21, CGA 6 | YES (to be modified) |
| 2 | Updated YAML frontmatter description (three modes) | Step 5 | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` (frontmatter) | NTA 1 | YES (to be modified) |
| 3 | Updated Step 1.5 with PR detection and three-mode routing | Step 6 | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` (Step 1.5) | NTA 3/4/13/14/15/19/20 | YES (to be modified) |
| 4 | Token count verification (≥1500 tokens headroom below 6500 ceiling) | Step 7 | Documented in commit message | NTA 7 | PENDING |

### Phase 2 Deliverables

| # | Deliverable | Impl Step | Expected Path | NTA/CPV Trace | Exists |
|---|-------------|-----------|---------------|---------------|--------|
| 5 | Code-review reconciliation mode (steps CR1-CR5) | Step 1 | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | NTA 2, CPV FR-2/FR-3/FR-4/FR-7 | YES (modified) |
| 6 | Scope boundary note (no `executing-qa` duplication) | Step 2 | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | NTA 12, CPV FR-5 | YES (to be modified) |
| 7 | Code-review reconciliation findings presentation | Step 3 | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` | NTA 10/11, CPV FR-7 | YES (to be modified) |
| 8 | Updated Verification Checklist with code-review reconciliation items | Step 4 | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` (checklist) | NTA 6 | YES (to be modified) |
| 9 | Updated "Relationship to Other Skills" section | Step 5 | `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` (bottom section) | NTA 5 | YES (to be modified) |
| 10 | Final token count under ~6500 tokens | Step 7 | Documented in commit message | NTA 7 | PENDING |
| 11 | `npm run validate` passes | Step 8 | CI/local validation | Existing Test row 1 | PENDING |

## Verification Checklist

- [ ] All existing tests pass (regression baseline) — `npm test` passes, specifically `build.test.ts`
- [ ] All FR-N entries (FR-1 through FR-8) have corresponding test plan entries in Code Path Verification
- [ ] All acceptance criteria (AC-1 through AC-11) are mapped to at least one test plan entry
- [ ] All implementation plan deliverables (11 verification entries decomposed from 9 formal deliverables across 2 phases) are mapped to NTA/CPV entries
- [ ] Coverage gaps are identified with recommendations (6 gaps documented)
- [ ] Code paths trace from requirements through implementation plan to SKILL.md locations
- [ ] New test recommendations are actionable and prioritized (23 entries in New Test Analysis)
- [ ] NFR-1 (performance), NFR-2 (error handling), NFR-3 (non-destructive) are covered in Code Path Verification
- [ ] Edge cases 1-9 from requirements are addressable via NTA entries or CGA manual verification (EC-3: NTA 14, EC-4: NTA 15, EC-5: NTA 17, EC-6: NTA 23, EC-7: NTA 22, EC-8: NTA 18, EC-9: NTA 19; EC-1/EC-2 via CGA 2)

### Acceptance Criteria Cross-Reference

| AC | Description | Test Plan Entry |
|----|-------------|-----------------|
| AC-1 | PR detection via branch naming or `--pr` flag | CPV FR-1, NTA 3/13/14/15/19 |
| AC-2 | Test plan entries flagged with specific descriptions | CPV FR-2, CGA 3 |
| AC-3 | GitHub issue update suggestions included | CPV FR-3, CGA 4 |
| AC-4 | Advisory requirements drift summary (no auto-fix) | CPV FR-4, NTA 12 (scope boundary covers no-auto-fix) |
| AC-5 | No duplication of `executing-qa` work | CPV FR-5, NTA 12 |
| AC-6 | Existing modes unchanged (behavioral semantics preserved) | CPV FR-6, NTA 8/9, CGA 6 |
| AC-7 | SKILL.md Relationship section updated | CPV FR-8, NTA 5 |
| AC-8 | Severity classification applies | CPV FR-7, NTA 10 |
| AC-9 | SKILL.md frontmatter updated | CPV FR-8, NTA 1 |
| AC-10 | Mode detection routes to all three modes | CPV FR-1, NTA 4/20, CGA 5 |
| AC-11 | Token budget respected | CPV FR-8, NTA 7/21 |
