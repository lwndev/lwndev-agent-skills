# Chore: Split Orchestrator SKILL.md

## Chore ID

`CHORE-032`

## GitHub Issue

[#142](https://github.com/lwndev/lwndev-marketplace/issues/142)

## Category

`refactoring`

## Description

Extract five sections from `orchestrating-workflows/SKILL.md` (currently 1,097 lines) into separate reference files using the progressive-disclosure pattern. SKILL.md navigates, references provide detail. Target: SKILL.md under 400 lines after extraction. This is a pure restructuring chore with no behavioral changes to the orchestrator.

## Affected Files

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (trimmed from ~1,097 to ~340 lines)
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/issue-tracking.md` (new, ~140 lines)
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` (new, ~180 lines)
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` (new, ~270 lines)
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/verification-and-relationships.md` (new, ~115 lines)
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` (unchanged)

## Acceptance Criteria

- [x] `references/issue-tracking.md` contains the full "Issue Tracking via `managing-work-items`" section (lines 40-178) verbatim
- [x] `references/chain-procedures.md` contains New Feature/Chore/Bug Workflow Procedures and Resume Procedure (lines 245-426) verbatim
- [x] `references/step-execution-details.md` contains chain-specific fork instructions, pause steps, phase loop, and PR creation (lines 607-837) verbatim
- [x] `references/verification-and-relationships.md` contains all verification checklists and "Relationship to Other Skills" section (lines 983-1098) verbatim
- [x] Model Selection section in SKILL.md trimmed to ~55 lines: worked examples A-D (lines 912-973) removed entirely; Axis 1 and Axis 2 tables replaced with one-line descriptions pointing to `references/model-selection.md`; Axis 3 override precedence table and baseline-locked step exceptions paragraph retained
- [x] Error Handling section (lines 975-982) remains in SKILL.md unchanged
- [x] SKILL.md is under 400 lines after all extractions
- [x] Each extracted section replaced with a 3-5 line summary and relative markdown link in SKILL.md
- [x] `npm run validate` passes after restructure
- [x] `npm test` passes after restructure
- [x] All reference files are Read-accessible from the skill via relative paths

## Completion

**Status:** `Complete`

**Completed:** 2026-04-12

**Pull Request:** Pending PR creation

## Notes

- Content must be moved verbatim; editorial changes are out of scope
- SKILL.md pointers should use relative markdown links (`[references/file.md](references/file.md)`) consistent with other skills
- The first ~5,000 tokens (post-compaction re-attachment window) should now cover frontmatter, arguments, Quick Start, step sequence tables, and the beginning of generic execution recipes
- `references/model-selection.md` already exists (600 lines) and is not modified
