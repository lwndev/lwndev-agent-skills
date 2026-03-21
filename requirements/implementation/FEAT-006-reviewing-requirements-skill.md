# Implementation Plan: Reviewing Requirements Skill

## Overview

This plan covers building the `reviewing-requirements` skill for the `lwndev-sdlc` plugin. The skill validates requirement documents against the codebase and documentation after drafting, closing the quality gap between `documenting-*` skills and `creating-implementation-plans`. The implementation is structured as a Claude Code skill (SKILL.md with assets/references) — not compiled code — so the phases focus on authoring the skill instructions, output templates, and integration with existing skills.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-006   | [#38](https://github.com/lwndev/lwndev-marketplace/issues/38) | [FEAT-006-reviewing-requirements-skill.md](../features/FEAT-006-reviewing-requirements-skill.md) | High | Medium | ✅ Complete |

## Recommended Build Sequence

### Phase 1: Skill Structure and Core Review Logic
**Feature:** [FEAT-006](../features/FEAT-006-reviewing-requirements-skill.md) | [#38](https://github.com/lwndev/lwndev-marketplace/issues/38)
**Status:** ✅ Complete

#### Rationale
- **Foundation first**: The SKILL.md is the entire runtime — it must be complete and well-structured before integration
- **Establishes workflow**: Defines the document resolution, verification checks, and output format that the skill follows
- **Self-contained**: Can be tested independently by invoking `/reviewing-requirements` on existing requirement docs
- **Highest value**: The core review logic is the primary deliverable; everything else is supplementary

#### Implementation Steps
1. Create skill directory structure: `plugins/lwndev-sdlc/skills/reviewing-requirements/`
2. Create `SKILL.md` with YAML frontmatter:
   - `name: reviewing-requirements`
   - `description`: Trigger phrases for skill matching
   - `allowed-tools`: Read, Glob, Grep, Edit, Write, Bash, Agent (needs Bash for `gh` issue validation, Agent for parallel verification)
3. Write the core SKILL.md sections:
   - **When to Use** — trigger conditions and skill scope
   - **Input** — document path or requirement ID (FEAT-XXX, CHORE-XXX, BUG-XXX)
   - **Step 1: Resolve Document** — ID-to-path resolution logic searching `requirements/features/`, `requirements/chores/`, `requirements/bugs/`, `requirements/implementation/`
   - **Step 2: Parse Document** — identify document type from ID prefix or file location, extract sections (FR-1)
   - **Step 3: Codebase Reference Verification** — instructions for extracting and verifying file paths, function names, class names using Glob/Grep/Read (FR-2)
   - **Step 4: Documentation Citation Verification** — how to identify and verify claims about framework behavior, library APIs (FR-3)
   - **Step 5: Internal Consistency Checks** — FR-to-acceptance-criteria mapping, edge case alignment, type-specific checks for bug RC-N traceability and plan phase dependencies (FR-4)
   - **Step 6: Gap Analysis** — missing error handling, untested paths, unstated assumptions (FR-5)
   - **Step 7: Cross-Reference Validation** — verify refs to other requirement docs and GitHub issues using `gh` CLI (FR-6)
   - **Step 8: Present Findings** — severity-organized output with Error/Warning/Info classification, category grouping, summary counts (FR-7)
   - **Step 9: Apply Fixes** — offer corrections with diff preview, require user approval (FR-8)
   - **Document Type Adaptations** — type-specific check variations for FEAT, CHORE, BUG, implementation plans (FR-9)
4. Create `assets/review-findings-template.md` — output template with severity sections, finding format, and summary structure
5. Create `references/` directory (initially empty — can add example review output after first real review)
6. Run `npm run validate` to ensure the skill passes plugin validation

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` — Complete skill with all review logic
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/assets/review-findings-template.md` — Findings output template
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/references/` — Reference directory
- [x] Skill passes `npm run validate`

---

### Phase 2: Documenting Skill Integration
**Feature:** [FEAT-006](../features/FEAT-006-reviewing-requirements-skill.md) | [#38](https://github.com/lwndev/lwndev-marketplace/issues/38)
**Status:** ✅ Complete

#### Rationale
- **Depends on Phase 1**: The skill must exist before other skills can recommend it
- **Completes the workflow chain**: Inserting `reviewing-requirements` between `documenting-*` and `creating-implementation-plans` requires the documenting skills to surface it
- **Low risk**: Small, additive change to three existing skills — appending a recommendation line

#### Implementation Steps
1. Update `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md`:
   - Add a closing recommendation section after the Verification Checklist advising users to run `/reviewing-requirements` before proceeding to implementation planning
2. Update `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md`:
   - Add the same closing recommendation after the Verification Checklist / Relationship to Other Skills section
3. Update `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md`:
   - Add the same closing recommendation after the Relationship to Other Skills section
4. Run `npm run validate` to ensure all modified skills still pass validation

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md` — Updated with review recommendation
- [x] `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md` — Updated with review recommendation
- [x] `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md` — Updated with review recommendation
- [x] All skills pass `npm run validate`

---

### Phase 3: Validation and Verification
**Feature:** [FEAT-006](../features/FEAT-006-reviewing-requirements-skill.md) | [#38](https://github.com/lwndev/lwndev-marketplace/issues/38)
**Status:** ✅ Complete

#### Rationale
- **Depends on Phases 1-2**: Validates the complete implementation
- **Catches integration issues**: Ensures the skill works end-to-end with real requirement documents
- **Quality gate**: Confirms findings are accurate, not generating false positives, and output format matches the template

#### Implementation Steps
1. Run the full test suite (`npm test`) to ensure no regressions
2. Run `npm run validate` for the complete plugin
3. Test the skill manually by invoking `/reviewing-requirements` on an existing feature requirement (e.g., `FEAT-005`)
4. Test ID resolution for each document type:
   - `FEAT-XXX` resolves to `requirements/features/`
   - `CHORE-XXX` resolves to `requirements/chores/`
   - `BUG-XXX` resolves to `requirements/bugs/`
   - Implementation plans resolve from `requirements/implementation/`
5. Verify the documenting skill integration by checking that each updated SKILL.md includes the recommendation
6. Bump plugin version in `plugins/lwndev-sdlc/.claude-plugin/plugin.json` (1.1.0 → 1.2.0) to reflect the new skill addition

#### Deliverables
- [x] All tests pass (`npm test`) — 260 passed, 17 suites
- [x] Full plugin validation passes (`npm run validate`) — 10/10 skills, 19/19 checks each
- [x] Manual test: review of an existing requirement document produces accurate findings
- [x] ID resolution works for all document types (FEAT in features/ and implementation/, CHORE in chores/, BUG in bugs/)
- [x] Plugin version bumped to 1.2.0
- [x] Documenting skills include review recommendation

---

## Shared Infrastructure

### Existing Patterns to Reuse
- **ID-to-path resolution**: The `documenting-qa` skill already implements ID parsing and document location logic (FEAT-XXX, CHORE-XXX, BUG-XXX). The `reviewing-requirements` skill should follow the same resolution pattern for consistency.
- **Subagent delegation**: Skills like `executing-qa` use the Agent tool for parallel verification. The `reviewing-requirements` skill may use agents for parallelizing independent verification checks (e.g., codebase refs and GitHub issue validation simultaneously).
- **Allowed tools pattern**: Existing skills declare `allowed-tools` in YAML frontmatter. This skill needs Read, Glob, Grep, Edit, Write, Bash (for `gh` CLI), and Agent.

### New Patterns Introduced
- **Severity-classified findings**: The Error/Warning/Info classification with category grouping is new to this plugin. The output template in `assets/review-findings-template.md` establishes this pattern for potential reuse.
- **Fix-with-approval workflow**: The pattern of presenting findings, then offering to apply fixes with diff preview is new. This could inform future skills that modify existing documents.

## Testing Strategy

### Automated Testing
- Plugin validation via `npm run validate` — ensures SKILL.md has valid frontmatter and required structure
- Existing test suite via `npm test` — ensures no regressions from skill file changes

### Manual Testing
- **Positive test**: Review a requirement document with known issues (incorrect file paths, missing acceptance criteria) and verify all issues are caught
- **Negative test**: Review a clean, well-formed requirement document and verify no false positives
- **Type coverage**: Test with FEAT, CHORE, BUG, and implementation plan documents
- **Fix workflow**: Test the fix application path with user approval
- **Integration**: Verify that after running a `documenting-*` skill, the output includes the recommendation to run `/reviewing-requirements`

## Dependencies and Prerequisites

### Prerequisites
- Existing `lwndev-sdlc` plugin structure in `plugins/lwndev-sdlc/`
- Existing requirement documents to test against (FEAT-001 through FEAT-005, any CHORE/BUG docs)
- `gh` CLI authenticated for GitHub issue validation
- `ai-skills-manager` installed for `npm run validate`

### No New External Dependencies
- The skill is a SKILL.md file with instructions — no npm packages, build steps, or compiled code required

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Skill instructions too vague → inconsistent review quality | High | Medium | Include specific examples and decision criteria for each check; add reference example of a completed review |
| False positives in codebase reference verification | Medium | Medium | Instruct skill to verify with Glob/Read before reporting; classify uncertain findings as Warning not Error |
| Skill too slow due to many codebase searches | Medium | Low | Instruct use of targeted searches (specific paths, not recursive scans); parallelize independent checks via Agent |
| Fix application introduces new errors | Medium | Low | Require diff preview before every change; default to review-only mode |
| Documenting skill changes break existing workflows | Low | Low | Changes are additive only (append recommendation); run full validation after changes |

## Success Criteria

### Phase-Level
- **Phase 1**: Skill exists, passes validation, and can review a requirement document producing categorized findings
- **Phase 2**: All three documenting skills include the review recommendation
- **Phase 3**: Full test suite passes, manual testing confirms accuracy, plugin version bumped

### Overall
- [ ] `reviewing-requirements` skill exists in `plugins/lwndev-sdlc/skills/`
- [ ] Skill correctly resolves requirement IDs to file paths
- [ ] Findings are organized by severity (Error/Warning/Info) and category
- [ ] Fix application requires user approval with diff preview
- [ ] Works with all document types (FEAT, CHORE, BUG, implementation plans)
- [ ] Documenting skills recommend running the review
- [ ] No regressions in existing skills or tests

## Code Organization

```
plugins/lwndev-sdlc/skills/
├── reviewing-requirements/          # NEW — Phase 1
│   ├── SKILL.md                     # Core skill with all review logic
│   ├── assets/
│   │   └── review-findings-template.md  # Output template
│   └── references/                  # Reference examples (populated after first review)
├── documenting-features/            # MODIFIED — Phase 2 (add recommendation)
│   └── SKILL.md
├── documenting-chores/              # MODIFIED — Phase 2 (add recommendation)
│   └── SKILL.md
└── documenting-bugs/                # MODIFIED — Phase 2 (add recommendation)
    └── SKILL.md
```
