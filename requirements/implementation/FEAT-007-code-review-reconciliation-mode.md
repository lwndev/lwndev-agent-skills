# Implementation Plan: Code-Review Reconciliation Mode

## Overview

Add a third operating mode to the `reviewing-requirements` skill that detects when a PR exists for a requirement and produces an advisory drift report. The implementation modifies a single file — the skill's `SKILL.md` — but must respect a tight token budget (~6500 tokens max) while adding substantial new content. This requires a two-phase approach: first creating headroom by trimming existing verbosity, then adding the new mode.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-007 | [#66](https://github.com/lwndev/lwndev-marketplace/issues/66) | [FEAT-007-code-review-reconciliation-mode.md](../features/FEAT-007-code-review-reconciliation-mode.md) | High | Medium | ✅ Complete |

## Recommended Build Sequence

### Phase 1: Token Budget Management and Mode Detection
**Feature:** [FEAT-007](../features/FEAT-007-code-review-reconciliation-mode.md) | [#66](https://github.com/lwndev/lwndev-marketplace/issues/66)
**Status:** ✅ Complete

#### Rationale
- The SKILL.md is currently ~5780 tokens (per #66 comment). The target ceiling is ~6500 tokens. Adding a full third mode requires ~1500-2000 tokens of new content, meaning ~800-1300 tokens must be trimmed from existing content first.
- Mode detection changes (Step 1.5) are structural — they affect how all three modes route, so they must be done carefully before adding the new mode's steps.
- Frontmatter and mode table updates set the stage for Phase 2 content.

#### Implementation Steps

1. **Measure current token count** — use a tokenizer or word-count heuristic (words × 1.3-1.5) to establish the exact baseline before any changes.

2. **Trim standard review steps (Steps 3-7)** — these contain the most verbose content and are candidates for condensing:
   - Consolidate Step 3 (Codebase Reference Verification): merge the File Paths, Function/Class Names, and Module/Package References subsections into a single condensed procedure. Remove the numbered sub-steps and use a compact bullet format.
   - Consolidate Step 4 (Documentation Citation Verification): reduce to a short paragraph with key guidance points instead of a numbered procedure.
   - Consolidate Step 5 (Internal Consistency Checks): keep the document-type tables but remove the bullet-list expansions under each type. The tables already communicate the check targets.
   - Consolidate Step 6 (Gap Analysis): merge the four subsections (Missing Error Handling, Untested Paths, Unstated Assumptions, Missing Edge Cases) into a single checklist-style paragraph.
   - Consolidate Step 7 (Cross-Reference Validation): merge the three subsections into a compact list.
   - **Target: save ~1000-1500 tokens from Steps 3-7 without losing any check that the skill must perform.**

3. **Trim test-plan reconciliation steps (R1-R7)** — apply similar condensing:
   - Merge the detailed extraction lists in Step R1 into a compact reference.
   - Condense Steps R2-R5 by removing redundant explanatory text while preserving the classification rules (Error/Warning/Info) and the specific checks.
   - Condense Step R6 and R7 by referencing the standard review presentation format rather than restating it.
   - **Target: save ~300-500 additional tokens.**

4. **Trim Document Type Adaptations section** — this section repeats information already implicit in the step-by-step procedures. Condense to a compact table or remove entirely if the steps already branch by document type.

5. **Update YAML frontmatter** — change the description to mention all three modes:
   ```yaml
   description: Validates requirement documents against the codebase and docs. Operates in three modes - standard review (before QA), test-plan reconciliation (after QA), and code-review reconciliation (after PR review). Use when the user says "review requirements", "validate requirements", "check requirements", or wants to verify a requirement document.
   ```

6. **Update Step 1.5 (Detect Review Mode)** — extend the mode detection logic:
   - After checking for a test plan, add a PR detection step using `gh pr list --head <branch-pattern>` for patterns `feat/{ID}-*`, `chore/{ID}-*`, `fix/{ID}-*`
   - Add `--pr` flag support for user-provided PR number
   - Add precedence rule: if both test plan and PR exist, code-review reconciliation takes precedence
   - Add handling for multiple PR matches, draft PRs, invalid `--pr` values
   - Update the mode display messages to include the new mode
   - Update the mode detection table to show all three modes with their triggers

7. **Measure token count after trimming** — verify headroom of at least ~1500 tokens below the 6500 ceiling before proceeding to Phase 2.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` — trimmed existing content (~1039 tokens saved: 799 words reduced from 3342 baseline)
- [x] Updated YAML frontmatter description (three modes)
- [x] Updated Step 1.5 with PR detection and three-mode routing
- [x] Token count verification: 2543 words (~3306 tokens) — ~3194 tokens headroom below 6500 ceiling

---

### Phase 2: Code-Review Reconciliation Steps and Metadata
**Feature:** [FEAT-007](../features/FEAT-007-code-review-reconciliation-mode.md) | [#66](https://github.com/lwndev/lwndev-marketplace/issues/66)
**Depends on:** Phase 1
**Status:** ✅ Complete

#### Rationale
- With token headroom established in Phase 1, the new mode's steps can be added.
- The code-review reconciliation steps are self-contained — they run when the mode is detected and produce advisory findings.
- The metadata updates (Relationship to Other Skills, Verification Checklist) finalize the skill's documentation.

#### Implementation Steps

1. **Add Code-Review Reconciliation Mode section** — insert after the Test-Plan Reconciliation Mode section, before Document Type Adaptations. Add steps CR1-CR5 (CR5 is findings presentation, implementing FR-7):

   - **Step CR1: Load PR Context** — fetch the PR diff using `gh pr diff <number>`, load the test plan (if exists), load the requirement document. If `gh` is unavailable, fall back to `git diff <base-branch>...HEAD`. Note: if test plan doesn't exist, skip CR2 and note as Info.

   - **Step CR2: Test Plan Staleness Detection** (FR-2) — compare test plan entries (Code Path Verification, New Test Analysis, Coverage Gap Analysis) against the PR diff. Flag entries referencing:
     - Changed function signatures or APIs
     - Removed or renamed files
     - Modified behavior
     For each flagged entry, describe specifically what changed.

   - **Step CR3: GitHub Issue Suggestions** (FR-3) — compare PR diff and requirements against the linked GitHub issue. Produce draft suggestions for scope changes, decisions made during review, and deferred work. Never post or modify the issue directly. If no GitHub issue is linked, skip and note as Info.

   - **Step CR4: Advisory Requirements Drift Summary** (FR-4) — compare PR diff against FR-N entries, acceptance criteria, and edge cases. Identify FRs not present in the diff, diff changes not described in any FR, and acceptance criteria that may not hold. Present as advisory only. Note that `executing-qa` reconciliation will handle actual document updates.

2. **Add scope boundary note** (FR-5) — add a brief callout in the code-review reconciliation section stating what this mode does NOT do: no affected files updates, no implementation plan modifications, no deviation summaries, no auto-fixes. Reference `executing-qa` as the downstream handler.

3. **Add Code-Review Reconciliation Findings Presentation** (FR-7) — add a subsection specifying:
   - Category grouping: Test Plan Staleness (CR2), GitHub Issue Suggestions (CR3), Requirements ↔ Code Drift (CR4)
   - Summary format: `Code-review reconciliation for {ID} (PR #{N}): Found **N errors**, **N warnings**, **N info**`
   - Same severity classification as existing modes
   - Reference the existing findings template for format consistency

4. **Update Verification Checklist** — add a "Code-Review Reconciliation" subsection:
   - [ ] PR detected and mode entered correctly
   - [ ] Test plan entries compared against PR diff (or skip noted if no test plan)
   - [ ] GitHub issue suggestions produced (or skip noted if no issue linked)
   - [ ] Advisory drift summary presented (no auto-fixes applied)
   - [ ] Scope boundary respected (no `executing-qa` work duplicated)
   - [ ] Findings organized by category with correct severity classification

5. **Update "Relationship to Other Skills" section** — add the code-review reconciliation workflow position:
   ```
   Features: documenting-features → reviewing-requirements → documenting-qa → reviewing-requirements → creating-implementation-plans → implementing-plan-phases → executing-qa
                                     (standard review)                          (reconciliation)

   Post-PR: PR review → reviewing-requirements (code-review reconciliation) → executing-qa
   ```
   Update the mode table to include:
   | **Review requirements (after PR review)** | **Use this skill — code-review reconciliation mode** |

6. **Verify FR-6 (existing mode preservation)** — diff the standard review steps (1-9) and test-plan reconciliation steps (R1-R7) against their Phase 1 state to confirm only trimming occurred, with no behavioral changes.

7. **Final token count verification** — measure the completed SKILL.md and confirm it is under ~6500 tokens. If over budget, identify and apply additional trims.

8. **Run `npm run validate`** — ensure the updated SKILL.md passes `ai-skills-manager` validation.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` — code-review reconciliation mode (steps CR1-CR5, scope boundary, findings presentation)
- [x] Updated Verification Checklist with code-review reconciliation items (8 checklist items)
- [x] Updated "Relationship to Other Skills" section with new workflow position and mode table entry
- [x] Final token count: 3158 words (~4105 tokens) — under ~6500 ceiling
- [x] `npm run validate` passes (11/11 skills, 19/19 checks)

---

## Shared Infrastructure

No new shared infrastructure required. This implementation modifies only the `reviewing-requirements` SKILL.md file. All referenced tools (`gh` CLI, `git diff`) are external dependencies already available in the skill's execution environment.

## Testing Strategy

### Automated Testing
- **`npm run validate`** — ensures SKILL.md passes `ai-skills-manager` validation after changes
- **`npm test`** — regression baseline; `scripts/__tests__/build.test.ts` validates the skill exists and passes validation
- **Created** `scripts/__tests__/reviewing-requirements.test.ts` (26 tests) validating SKILL.md content (frontmatter, required sections, three-mode documentation, code-review reconciliation content, allowed-tools, asset files, API validation)

### Manual Testing
- Invoke `/reviewing-requirements` on a requirement ID with an associated PR to verify code-review reconciliation mode activates
- Invoke on a requirement ID with a test plan but no PR to verify test-plan reconciliation mode still works
- Invoke on a requirement ID with neither to verify standard review still works
- Test edge cases: draft PR, multiple matching PRs, `--pr` flag, missing test plan, missing GitHub issue

## Dependencies and Prerequisites

- `gh` CLI authenticated and available (external dependency)
- Current `reviewing-requirements` SKILL.md at its post-#68 state (~5780 tokens baseline)
- QA test plan `qa/test-plans/QA-plan-FEAT-007.md` exists for post-implementation verification

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Token budget exceeded after adding new mode | High | Medium | Phase 1 creates headroom first; measure after each phase; aggressive trimming targets identified |
| Trimming existing steps loses behavioral nuance | Medium | Medium | Diff standard review and test-plan reconciliation before/after; preserve all check types and classification rules |
| `ai-skills-manager` validation rejects modified SKILL.md | Medium | Low | Run `npm run validate` after each phase; fix structural issues immediately |
| Existing modes regress due to structural changes | High | Low | Git diff comparison of existing mode sections; manual invocation testing of all three modes |
| PR detection via `gh pr list` is slow or unreliable | Low | Low | `--pr` flag provides manual fallback; mode falls through gracefully if no PR detected |

## Success Criteria

- [x] SKILL.md contains all three modes: standard review, test-plan reconciliation, code-review reconciliation
- [x] Token count is under ~6500 tokens (3180 words, ~4134 tokens)
- [x] `npm run validate` passes (11/11 skills, 19/19 checks)
- [x] `npm test` passes (306/306 tests across 19 files)
- [x] All 11 acceptance criteria from FEAT-007 are addressed (verified by QA execution)
- [x] Existing modes produce identical behavior (verified by git diff of their sections)
- [x] Code-review reconciliation mode produces advisory findings in the three specified categories

## Code Organization

```
plugins/lwndev-sdlc/skills/reviewing-requirements/
├── SKILL.md                            # Modified: three-mode skill definition
└── assets/
    └── review-findings-template.md     # Unchanged: reused by all modes
```
