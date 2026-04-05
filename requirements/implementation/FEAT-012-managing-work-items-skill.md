# Implementation Plan: Managing Work Items Skill

## Overview

Create a new `managing-work-items` skill that centralizes all issue tracker operations (GitHub Issues and Jira) into a single, delegatable skill invoked by the orchestrator. The skill handles two operations -- fetch and comment -- with automatic backend detection from issue reference format (`#N` for GitHub, `PROJ-123` for Jira). Issue close/transition is deferred to a follow-up task due to Jira workflow complexity (dynamic transition IDs, project-specific status names); GitHub auto-close is handled by `Closes #N` in PR bodies and Jira auto-transition by branch naming conventions. Jira support uses a tiered fallback (Rovo MCP, `acli` CLI, skip). After the new skill is established, existing execution skills (`implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`) are refactored to remove their inline `gh issue` operations and github-templates references, and `documenting-features` is updated to delegate issue fetch. Finally, the `orchestrating-workflows` skill is updated with `managing-work-items` invocation points at each workflow stage.

This is a single feature (FEAT-012) divided into five phases that follow a foundation-first approach: create the new skill with GitHub support, add Jira support, refactor execution skills, refactor documentation skills, and update the orchestrator.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-012 | [#119](https://github.com/lwndev/lwndev-marketplace/issues/119) | [FEAT-012-managing-work-items-skill.md](../features/FEAT-012-managing-work-items-skill.md) | High | High | Pending |

## Recommended Build Sequence

### Phase 1: Create Managing Work Items Skill -- GitHub Backend
**Feature:** [FEAT-012](../features/FEAT-012-managing-work-items-skill.md) | [#119](https://github.com/lwndev/lwndev-marketplace/issues/119)
**Status:** ✅ Complete

#### Rationale
- Foundation that all subsequent phases depend on -- the skill structure, SKILL.md, and GitHub backend must exist before Jira support, refactoring, or orchestrator integration
- GitHub Issues is the primary backend used by all existing workflows in this repository, so it must work first
- Consolidates the three existing `references/github-templates.md` files (from `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`) into a single authoritative location
- Creates the `references/jira-templates.md` file as a placeholder structure (populated with content in Phase 2)
- Backend detection logic (FR-1) and issue reference extraction (FR-8) are implemented here because they are prerequisites for every operation
- Establishes the invocation syntax (`fetch`, `comment`) and argument parsing that the orchestrator will use in Phase 5

#### Implementation Steps
1. Create the skill directory structure:
   ```
   plugins/lwndev-sdlc/skills/managing-work-items/
   ├── SKILL.md
   └── references/
       ├── github-templates.md
       └── jira-templates.md
   ```
2. Write `SKILL.md` with YAML frontmatter (`name: managing-work-items`, `description`, `allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]`, `argument-hint: "<operation> <issue-ref> [--type <comment-type>] [--context <json>]"`)
3. Implement backend detection logic in SKILL.md instructions (FR-1): parse `#N` as GitHub, `PROJ-123` (alphabetic project key + `-` + number) as Jira, empty/absent as skip-all
4. Implement GitHub Issues backend operations in SKILL.md (FR-2):
   - **fetch**: `gh issue view <N> --json title,body,labels,state,assignees` -- return structured data
   - **comment**: `gh issue comment <N> --body "<formatted-comment>"` -- format using comment type templates
5. Implement comment type routing (FR-5): map `--type` argument to the correct template (`phase-start`, `phase-completion`, `work-start`, `work-complete`, `bug-start`, `bug-complete`)
6. Implement PR body issue link generation (FR-6): output `Closes #N` for GitHub, `PROJ-123` for Jira
7. Implement issue reference extraction from documents (FR-7): parse `## GitHub Issue` section for `[#N](URL)` or `[PROJ-123](URL)` patterns; return null if section is empty or missing
8. Document graceful degradation behavior (NFR-1): if `gh` CLI fails (not authenticated, network unavailable, rate limited), log a warning and skip without blocking workflow
9. Document error handling (NFR-2): command failures log full output and skip; authentication errors give clear remediation messages
10. Document idempotency behavior (NFR-3): comment operations safe to retry
11. Create `references/github-templates.md` by consolidating templates from:
    - `implementing-plan-phases/references/github-templates.md` (phase-start, phase-completion)
    - `executing-chores/references/github-templates.md` (work-start, work-complete, commit messages, PR body, issue creation)
    - `executing-bug-fixes/references/github-templates.md` (bug-start, bug-complete, commit messages, PR body, issue creation)
    Organize under a unified structure with comment type sections matching the `--type` argument values, plus separate sections for commit messages, PR templates, and issue creation (carried over from the source files for completeness)
12. Create `references/jira-templates.md` with placeholder ADF JSON structure matching the same comment types -- mark each template as "TODO: Phase 2" so the file exists but content is deferred. Include a reference to the [ADF specification](https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/) at the top of the file
13. Add unit tests to `scripts/__tests__/managing-work-items.test.ts`:
    - Skill directory exists with expected structure
    - SKILL.md passes `validate()` from `ai-skills-manager`
    - SKILL.md frontmatter contains correct `name`, `description`, `allowed-tools`, `argument-hint`
    - `references/github-templates.md` exists and contains all six comment type templates
    - `references/jira-templates.md` exists
14. Run `npm run validate` to confirm the new skill passes validation
15. Run `npm test` to confirm all tests pass (new + existing)

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md` -- skill instructions with backend detection, GitHub operations, comment type routing, PR link generation, document extraction, graceful degradation
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/references/github-templates.md` -- consolidated GitHub comment templates (phase-start, phase-completion, work-start, work-complete, bug-start, bug-complete) plus commit message, PR body, and issue creation templates
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/references/jira-templates.md` -- placeholder Jira templates with structure matching GitHub templates
- [x] `scripts/__tests__/managing-work-items.test.ts` -- skill structure and validation tests

---

### Phase 2: Add Jira Backend Support
**Feature:** [FEAT-012](../features/FEAT-012-managing-work-items-skill.md) | [#119](https://github.com/lwndev/lwndev-marketplace/issues/119)
**Status:** ✅ Complete
**Depends on:** Phase 1 (skill structure, SKILL.md, backend detection)

#### Rationale
- Builds on the backend detection logic from Phase 1 -- the `PROJ-123` format path now needs a real implementation instead of the "no Jira backend available, skipping" fallback
- Jira support is the primary motivation for FEAT-012 (prerequisite for issue #118) so it must be complete before refactoring existing skills
- Tiered fallback (Rovo MCP, `acli`, skip) is self-contained and does not affect the GitHub backend path
- Completing Jira support before refactoring ensures the new skill handles both backends fully before other skills delegate to it
- The `references/jira-templates.md` placeholder from Phase 1 is populated with real templates here

#### Implementation Steps
1. Add Jira backend tiered fallback logic to SKILL.md (FR-3):
   - **Tier 1 -- Rovo MCP**: Check if the `rovo` MCP server is available; if present, use Rovo MCP tools (`getJiraIssue`, `addCommentToJiraIssue`). Comments must be in Atlassian Document Format (ADF) JSON — see FR-8
   - **Tier 2 -- Atlassian CLI (`acli`)**: Check if `acli` is on PATH; if present, use `acli jira workitem` subcommands (`view`, `comment-create`). `acli` accepts markdown and handles ADF conversion internally
   - **Tier 3 -- Skip**: If neither backend is available, log a warning and skip without failing
2. Implement Jira fetch operation: retrieve issue details (title, description, labels/tags, status, assignees) via the selected backend
3. Implement Jira comment operation: post formatted comments using Jira-specific templates from `references/jira-templates.md`. For the Rovo MCP path, comments must be in ADF JSON format (FR-8); for the `acli` path, markdown is acceptable as `acli` handles ADF conversion internally
4. Implement Jira PR body link generation (FR-6): output `PROJ-123` for Jira (relies on branch name containing the key for Jira auto-transition)
5. Populate `references/jira-templates.md` with ADF JSON templates for all six comment types (`phase-start`, `phase-completion`, `work-start`, `work-complete`, `bug-start`, `bug-complete`), producing equivalent information to the GitHub markdown templates but using ADF constructs per FR-8: `heading` nodes instead of `##`, `marks` for bold/italic, `bulletList`/`listItem` for lists, `panel` nodes for status callouts, `codeBlock` for code snippets
7. Document Jira-specific error handling: authentication errors for Rovo MCP and `acli` give clear remediation messages; tiered fallback logs which tier was attempted and why it was skipped
8. Handle edge case: `PROJ2-123` format (alphanumeric project keys) -- ensure the regex in backend detection correctly handles project keys with numbers
9. Add tests to `scripts/__tests__/managing-work-items.test.ts`:
   - SKILL.md contains Jira backend tiered fallback documentation
   - SKILL.md contains Rovo MCP and `acli` operation documentation
   - `references/jira-templates.md` contains all six comment type templates in ADF JSON format (no longer placeholder)
   - Jira ADF templates are valid ADF (contain `"version": 1`, `"type": "doc"`, `"content"` array) per FR-8
   - Jira templates include work item ID traceability (FEAT-XXX, CHORE-XXX, BUG-XXX) per NFR-4
   - Bug-related Jira templates preserve RC-N tagging per NFR-4
10. Run `npm run validate` and `npm test`

#### Deliverables
- [x] Updated `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md` -- Jira backend tiered fallback (Rovo MCP, `acli`, skip), Jira operations (fetch, comment), Jira error handling
- [x] Updated `plugins/lwndev-sdlc/skills/managing-work-items/references/jira-templates.md` -- complete Jira comment templates in ADF JSON format for all six types (FR-8)
- [x] Updated `scripts/__tests__/managing-work-items.test.ts` -- Jira backend validation tests

---

### Phase 3: Refactor Execution Skills
**Feature:** [FEAT-012](../features/FEAT-012-managing-work-items-skill.md) | [#119](https://github.com/lwndev/lwndev-marketplace/issues/119)
**Status:** ✅ Complete
**Depends on:** Phase 1 (consolidated github-templates.md in managing-work-items), Phase 2 (complete Jira support)

#### Rationale
- The execution skills (`implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`) contain the heaviest issue tracker duplication -- inline `gh issue comment` instructions, `Closes #N` patterns, and references to per-skill `github-templates.md` files
- Must come after Phases 1 and 2 so that the replacement skill is fully functional for both backends before removing the inline operations
- Removes three `github-templates.md` files from the source skills and replaces them with references to the centralized skill
- The SKILL.md instructions for each execution skill are simplified: issue operations become "the orchestrator handles issue tracking via `managing-work-items`" rather than inline `gh issue` commands
- Does not change the execution logic (branch creation, implementation, PR creation) -- only removes the issue tracking responsibilities

#### Implementation Steps
1. **Refactor `implementing-plan-phases/SKILL.md`**:
   - Remove step 4 ("Update GitHub issue with phase start") and step 11 ("Update GitHub issue with completion comment") from the Quick Start and Workflow Checklist sections
   - Remove the inline `gh issue comment` code blocks from steps 4 and 11
   - Remove the "Post GitHub issue start comment" and "Post GitHub issue completion comment" checklist items
   - Update the description frontmatter to remove "GitHub issue comments" from the description
   - Add a note: "Issue tracking (start/completion comments) is handled by the orchestrator via `managing-work-items`. This skill focuses on implementation, verification, and status tracking."
   - Keep the `Closes #N` requirement in PR creation (step 12) -- this is still generated by the skill or orchestrator using FR-6
   - Update the References section: remove the `github-templates.md` reference line
2. **Refactor `implementing-plan-phases/references/`**:
   - Delete `implementing-plan-phases/references/github-templates.md`
   - Update `implementing-plan-phases/references/step-details.md`: remove Step 4 (Update GitHub Issue Start) and Step 11 (Update GitHub Issue Completion) content, or replace with a note that issue tracking is delegated to `managing-work-items`. Update the Table of Contents accordingly. Keep Step 12 (Create Pull Request) intact
3. **Refactor `executing-chores/SKILL.md`**:
   - Remove step 4 ("Post start comment on GitHub issue") from Quick Start
   - Remove the "Post GitHub issue start comment (if issue exists)" checklist item from the Workflow Checklist
   - Remove the "Note GitHub issue number from chore document (if linked)" checklist item (extraction is now FR-7 in `managing-work-items`)
   - Add a note: "Issue tracking (start/completion comments) is handled by the orchestrator via `managing-work-items`."
   - Keep the `Closes #N` PR body requirement -- this is still used for auto-close
   - Update the References section: remove the `github-templates.md` reference line
4. **Refactor `executing-chores/references/`**:
   - Delete `executing-chores/references/github-templates.md`
   - Update `executing-chores/references/workflow-details.md`: remove Step 2 (Check GitHub Issue) and Step 10 (Update GitHub Issue) content, or replace with a delegation note. Update the Table of Contents accordingly
5. **Refactor `executing-bug-fixes/SKILL.md`**:
   - Remove step 4 ("Note GitHub issue number if linked") and step 5 ("Post start comment on GitHub issue") from Quick Start
   - Remove the "Note GitHub issue number from bug document (if linked)" and "Post GitHub issue start comment with root causes (if issue exists)" checklist items
   - Add a note: "Issue tracking (start/completion comments) is handled by the orchestrator via `managing-work-items`."
   - Keep the `Closes #N` PR body requirement
   - Update the References section: remove the `github-templates.md` reference line
6. **Refactor `executing-bug-fixes/references/`**:
   - Delete `executing-bug-fixes/references/github-templates.md`
   - Update `executing-bug-fixes/references/workflow-details.md`: remove Step 3 (Check GitHub Issue) and Step 13 (Update GitHub Issue) content, or replace with a delegation note. Update the Table of Contents accordingly
7. Verify the commit message and PR body template sections in `executing-chores/references/github-templates.md` and `executing-bug-fixes/references/github-templates.md` are already captured in the consolidated `managing-work-items/references/github-templates.md` (done in Phase 1, step 11). If any templates were missed, add them to the consolidated file before deleting the source files
8. Run `npm run validate` to confirm all three refactored skills still pass validation
9. Run `npm test` to confirm all existing tests pass -- update any tests that assert on the removed `github-templates.md` files or the removed SKILL.md content
10. Add/update tests in `scripts/__tests__/implementing-plan-phases.test.ts`, `scripts/__tests__/executing-chores.test.ts`, `scripts/__tests__/executing-bug-fixes.test.ts`:
    - Verify `references/github-templates.md` no longer exists in each skill directory
    - Verify SKILL.md no longer contains inline `gh issue comment` instructions (for `implementing-plan-phases`)
    - Verify SKILL.md contains delegation note referencing `managing-work-items`

#### Deliverables
- [x] Updated `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` -- removed inline `gh issue` operations, added delegation note
- [x] Updated `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` -- removed/replaced GitHub issue steps
- [x] Deleted `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/github-templates.md`
- [x] Updated `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` -- removed inline issue operations, added delegation note
- [x] Updated `plugins/lwndev-sdlc/skills/executing-chores/references/workflow-details.md` -- removed/replaced GitHub issue steps
- [x] Deleted `plugins/lwndev-sdlc/skills/executing-chores/references/github-templates.md`
- [x] Updated `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` -- removed inline issue operations, added delegation note
- [x] Updated `plugins/lwndev-sdlc/skills/executing-bug-fixes/references/workflow-details.md` -- removed/replaced GitHub issue steps
- [x] Deleted `plugins/lwndev-sdlc/skills/executing-bug-fixes/references/github-templates.md`
- [x] Updated tests in `scripts/__tests__/implementing-plan-phases.test.ts`, `scripts/__tests__/executing-chores.test.ts`, `scripts/__tests__/executing-bug-fixes.test.ts`

---

### Phase 4: Refactor Documentation Skill
**Feature:** [FEAT-012](../features/FEAT-012-managing-work-items-skill.md) | [#119](https://github.com/lwndev/lwndev-marketplace/issues/119)
**Status:** ✅ Complete
**Depends on:** Phase 1 (managing-work-items fetch operation)

#### Rationale
- `documenting-features` currently fetches GitHub issue content inline when invoked with `#N` argument -- this is the issue fetch operation (FR-4) that should be delegated to `managing-work-items`
- Lighter touch than Phase 3 -- only one skill to modify, and the change is replacing an inline fetch with a delegation instruction
- Separated from Phase 3 because documentation skills have different refactoring scope (fetch delegation vs. comment removal) and different testing concerns
- `documenting-chores` and `documenting-bugs` only store issue links (no inline operations to remove per the requirements), so no changes needed for those skills

#### Implementation Steps
1. **Update `documenting-features/SKILL.md`**:
   - Modify the Arguments section: change the `#<number>` handling from "fetch the corresponding GitHub issue" to "delegate to the orchestrator or `managing-work-items fetch #N` to retrieve issue data, then use the returned title and body to pre-fill the requirements template"
   - Add a note explaining that direct `gh` CLI usage for issue fetch is replaced by the centralized `managing-work-items` skill
   - Keep the graceful degradation behavior: if the fetch fails, warn and continue with manual input
   - Keep the `argument-hint: "[feature-name or #issue-number]"` unchanged -- the argument format is the same, only the implementation path changes
2. Verify `documenting-chores` and `documenting-bugs` SKILL.md files do not contain inline issue fetch operations (confirmed during analysis: they only store issue links, no operations to remove)
3. Update tests in `scripts/__tests__/documenting-features.test.ts`:
   - Verify SKILL.md still accepts `#N` argument format
   - Verify SKILL.md references `managing-work-items` for issue fetch delegation
4. Run `npm run validate` and `npm test`

#### Deliverables
- [x] Updated `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md` -- delegated issue fetch to `managing-work-items`
- [x] Updated `scripts/__tests__/documenting-features.test.ts` -- updated test assertions for delegation

---

### Phase 5: Update Orchestrator with Managing Work Items Invocation Points
**Feature:** [FEAT-012](../features/FEAT-012-managing-work-items-skill.md) | [#119](https://github.com/lwndev/lwndev-marketplace/issues/119)
**Status:** ✅ Complete
**Depends on:** Phase 1 (managing-work-items skill exists), Phase 2 (Jira support complete), Phase 3 (execution skills refactored), Phase 4 (documentation skill refactored)

#### Rationale
- Final phase because the orchestrator depends on every other change being in place: the new skill must exist (Phase 1), Jira must work (Phase 2), execution skills must no longer handle issue operations themselves (Phase 3), and documentation skills must delegate fetch (Phase 4)
- The orchestrator is the integration point that ties everything together -- it invokes `managing-work-items` at the correct workflow points and passes the right operation, issue reference, comment type, and context
- Changes are additive to the existing orchestrator SKILL.md (new invocation points inserted between existing steps) rather than replacing existing steps
- All three chain types (feature, chore, bug) need updated step sequences with `managing-work-items` invocations

#### Implementation Steps
1. **Add `managing-work-items` invocation points to the Feature Chain** in `orchestrating-workflows/SKILL.md`:
   - After step 1 (documenting-features): invoke `managing-work-items fetch <issue-ref>` to pre-fill requirements when `#N` argument is provided
   - Before each phase step (steps 7...6+N): invoke `managing-work-items comment <issue-ref> --type phase-start --context <json>`
   - After each phase step: invoke `managing-work-items comment <issue-ref> --type phase-completion --context <json>`
   - At PR creation (step 6+N+1): use `managing-work-items` FR-6 to generate the `Closes #N` or `PROJ-123` link for the PR body
2. **Add `managing-work-items` invocation points to the Chore Chain**:
   - Before step 5 (executing-chores): invoke `managing-work-items comment <issue-ref> --type work-start --context <json>`
   - After step 5: invoke `managing-work-items comment <issue-ref> --type work-complete --context <json>`
   - At PR creation in step 5 output: use FR-6 for issue link
3. **Add `managing-work-items` invocation points to the Bug Chain**:
   - Before step 5 (executing-bug-fixes): invoke `managing-work-items comment <issue-ref> --type bug-start --context <json>`
   - After step 5: invoke `managing-work-items comment <issue-ref> --type bug-complete --context <json>`
   - At PR creation in step 5 output: use FR-6 for issue link
4. **Document the issue reference flow**: explain how the orchestrator extracts the issue reference from the requirements document (using FR-7 from `managing-work-items`) at workflow start and passes it through to all subsequent invocations
5. **Document skip behavior**: when no issue reference is found in the requirements document, all `managing-work-items` invocations are skipped with an info-level message; workflow continues normally
6. **Add `managing-work-items` to the Relationship to Other Skills section**: update the feature chain, chore chain, and bug chain diagrams to show where `managing-work-items` is invoked
7. Update the **Verification Checklist** with managing-work-items checks: issue comments posted at correct points, graceful skip when no issue linked
8. Add tests to `scripts/__tests__/orchestrating-workflows.test.ts`:
   - SKILL.md references `managing-work-items` skill
   - SKILL.md contains invocation points for all three chain types
   - SKILL.md documents fetch and comment operations at correct workflow points
9. Run `npm run validate` and `npm test`

#### Deliverables
- [x] Updated `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` -- `managing-work-items` invocation points for feature, chore, and bug chains; issue reference flow documentation; skip behavior; updated relationship diagrams; updated verification checklist
- [x] Updated `scripts/__tests__/orchestrating-workflows.test.ts` -- managing-work-items integration assertions

---

## Shared Infrastructure

### New Skill
- `plugins/lwndev-sdlc/skills/managing-work-items/` -- the centralized issue tracker skill created in Phase 1 and enhanced in Phase 2

### Consolidated Templates
- `managing-work-items/references/github-templates.md` -- single source of truth for all GitHub issue comment templates, commit message formats, PR body templates, and issue creation templates (replaces three separate files)
- `managing-work-items/references/jira-templates.md` -- equivalent Jira templates in ADF JSON format for all comment types

### Invocation Syntax
All operations use a consistent invocation pattern:
```
managing-work-items <operation> <issue-ref> [--type <comment-type>] [--context <json>]
```

Operations: `fetch`, `comment`
Comment types: `phase-start`, `phase-completion`, `work-start`, `work-complete`, `bug-start`, `bug-complete`

### Backend Detection
- `#N` format -> GitHub Issues backend (via `gh` CLI)
- `PROJ-123` format -> Jira backend (via tiered fallback: Rovo MCP, `acli`, skip)
- Empty/absent -> skip all operations gracefully

## Testing Strategy

### Unit Tests
- **Framework:** vitest with `ai-skills-manager` `validate()` API
- **New test file:** `scripts/__tests__/managing-work-items.test.ts`
  - Skill directory structure validation
  - SKILL.md frontmatter and structural validation
  - Template file existence and content validation (both GitHub and Jira)
  - Backend detection documentation coverage
  - Comment type coverage (all six types documented)

### Existing Test Updates
- `scripts/__tests__/implementing-plan-phases.test.ts` -- verify github-templates.md removed, delegation note present
- `scripts/__tests__/executing-chores.test.ts` -- verify github-templates.md removed, delegation note present
- `scripts/__tests__/executing-bug-fixes.test.ts` -- verify github-templates.md removed, delegation note present
- `scripts/__tests__/documenting-features.test.ts` -- verify delegation to managing-work-items
- `scripts/__tests__/orchestrating-workflows.test.ts` -- verify managing-work-items invocation points

### Manual Testing
- Run a complete feature chain and verify issue comments appear at each stage (phase start, phase completion)
- Run a chore chain with a linked GitHub issue and verify start/completion comments
- Run a bug chain and verify RC-N traceability in issue comments
- Test with no issue linked -- verify no errors and clean workflow progression
- Test with Jira reference if Jira environment is available
- Verify all refactored skills continue to function correctly in standalone mode
- Verify orchestrated workflows produce the same issue tracking behavior as before refactoring

### Regression Testing
- All existing tests must continue to pass after each phase
- Run `npm run validate` after each phase to confirm all skills pass validation
- Specifically verify that the three execution skills produce correct PRs with `Closes #N` after refactoring (the auto-close mechanism must not break)

## Dependencies and Prerequisites

### Internal Dependencies
- All 12 existing skills under `plugins/lwndev-sdlc/skills/` -- 4 are modified (implementing-plan-phases, executing-chores, executing-bug-fixes, documenting-features), 1 is extended (orchestrating-workflows), 7 are unchanged
- `ai-skills-manager` programmatic API -- `validate()` for skill validation in tests
- vitest test infrastructure -- existing test files and patterns

### External Dependencies
- `gh` CLI -- GitHub Issues backend (required for current workflows, unchanged)
- Rovo MCP server -- Jira primary backend (optional, new)
- `acli` CLI -- Jira fallback backend (optional, new)
- `jq` -- JSON manipulation in orchestrator state scripts (existing dependency)

### Phase Dependencies
```
Phase 1 (GitHub backend) ─────────────┬──> Phase 3 (refactor execution)
                                      ├──> Phase 4 (refactor documentation)
Phase 2 (Jira backend) ──────────────┤
                                      └──> Phase 5 (update orchestrator)
Phase 3 + Phase 4 ───────────────────────> Phase 5
```

Phase 1 and Phase 2 are sequential (Phase 2 builds on Phase 1). Phases 3 and 4 depend on Phases 1 and 2. Phase 5 depends on all prior phases.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Refactoring execution skills breaks existing workflows | High | Medium | Phase 3 explicitly preserves `Closes #N` in PR creation; manual testing of each execution skill standalone and orchestrated after refactoring; existing tests provide regression coverage |
| Consolidated github-templates.md misses templates from source files | Medium | Low | Phase 1 step 11 explicitly lists all source files; Phase 3 step 7 verifies completeness before deleting source files; templates are checked in tests |
| Orchestrator SKILL.md grows too large with new invocation points | Medium | Medium | Invocation points follow a consistent pattern and can reference `managing-work-items` SKILL.md for details rather than duplicating operation documentation; keep orchestrator instructions concise |
| Jira tiered fallback adds complexity to an already large SKILL.md | Medium | Medium | Phase 2 is self-contained; Jira logic is clearly separated from GitHub logic with independent sections; fallback tiers are documented as a simple sequential check |
| `managing-work-items` SKILL.md becomes too verbose for Claude context | Medium | Low | Keep operation documentation focused on invocation and delegation; detailed templates live in reference files, not inline in SKILL.md |
| Removing `github-templates.md` from execution skills breaks PR template references | Low | Medium | PR templates (`assets/pr-template.md`) are separate from issue comment templates; verify that `references/workflow-details.md` in each skill still references the correct PR template path after refactoring |
| Rovo MCP availability detection unreliable | Low | Medium | Tiered fallback ensures graceful degradation; if Rovo MCP detection fails, `acli` is tried, then skip; never blocks workflow |
| Edge case: alphanumeric Jira project keys (e.g., `PROJ2-123`) | Low | Low | Phase 2 step 8 explicitly addresses this with regex testing |

## Success Criteria

- [ ] `managing-work-items` skill exists at `plugins/lwndev-sdlc/skills/managing-work-items/` with valid SKILL.md
- [ ] Skill handles fetch and comment operations for GitHub Issues via `gh` CLI
- [ ] Skill includes backend detection logic (GitHub `#N` vs Jira `PROJ-123`)
- [ ] Jira operations supported via Rovo MCP (primary) and `acli` (fallback) with graceful skip
- [ ] Graceful degradation when no Jira backend is available (skip without error)
- [ ] Graceful degradation when `gh` CLI fails (skip without blocking workflow)
- [ ] `references/github-templates.md` consolidated from three skills into `managing-work-items`
- [ ] `references/jira-templates.md` created with equivalent templates for Jira in ADF JSON format (FR-8)
- [ ] `implementing-plan-phases` SKILL.md no longer contains inline `gh issue` operations
- [ ] `executing-chores` SKILL.md no longer contains inline `gh issue` operations
- [ ] `executing-bug-fixes` SKILL.md no longer contains inline `gh issue` operations
- [ ] `documenting-features` delegates issue fetch to `managing-work-items`
- [ ] Orchestrator SKILL.md updated with `managing-work-items` invocation points for all three chain types
- [ ] All existing workflows continue to function (regression verified)
- [ ] All skills pass `npm run validate`
- [ ] All tests pass `npm test`
- [ ] Issue reference extraction from documents works for both `#N` and `PROJ-123` formats

## Code Organization

```
plugins/lwndev-sdlc/skills/
├── managing-work-items/                    # Phase 1 + 2: NEW skill
│   ├── SKILL.md                           # Backend detection, operations, error handling
│   └── references/
│       ├── github-templates.md            # Phase 1: Consolidated from 3 skills
│       └── jira-templates.md              # Phase 1: Placeholder; Phase 2: Complete (ADF JSON format)
├── implementing-plan-phases/
│   ├── SKILL.md                           # Phase 3: Remove inline gh issue operations
│   └── references/
│       ├── step-details.md                # Phase 3: Remove GitHub issue steps
│       ├── workflow-example.md            # Unchanged
│       └── github-templates.md            # Phase 3: DELETED
├── executing-chores/
│   ├── SKILL.md                           # Phase 3: Remove inline issue operations
│   └── references/
│       ├── workflow-details.md            # Phase 3: Remove GitHub issue steps
│       └── github-templates.md            # Phase 3: DELETED
├── executing-bug-fixes/
│   ├── SKILL.md                           # Phase 3: Remove inline issue operations
│   └── references/
│       ├── workflow-details.md            # Phase 3: Remove GitHub issue steps
│       └── github-templates.md            # Phase 3: DELETED
├── documenting-features/
│   ├── SKILL.md                           # Phase 4: Delegate issue fetch
│   └── references/                        # Unchanged
├── orchestrating-workflows/
│   ├── SKILL.md                           # Phase 5: Add managing-work-items invocations
│   └── scripts/                           # Unchanged
└── [7 other skills unchanged]

scripts/__tests__/
├── managing-work-items.test.ts            # Phase 1 + 2: NEW test file
├── implementing-plan-phases.test.ts       # Phase 3: Updated assertions
├── executing-chores.test.ts               # Phase 3: Updated assertions
├── executing-bug-fixes.test.ts            # Phase 3: Updated assertions
├── documenting-features.test.ts           # Phase 4: Updated assertions
└── orchestrating-workflows.test.ts        # Phase 5: Updated assertions
```
