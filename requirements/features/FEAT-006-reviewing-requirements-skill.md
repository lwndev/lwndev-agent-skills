# Feature Requirements: Reviewing Requirements Skill

## Overview

Add a standalone `reviewing-requirements` skill to the `lwndev-sdlc` plugin that validates requirement documents against the codebase and documentation after drafting, catching errors before they propagate into implementation plans and code.

## Feature ID
`FEAT-006`

## GitHub Issue
[#38](https://github.com/lwndev/lwndev-marketplace/issues/38)

## Priority
High - Closes a quality gap in the SDLC workflow; errors in requirements propagate into plans and code if not caught early.

## User Story

As a developer using the SDLC plugin, I want to validate my requirement documents against the codebase and docs so that I can catch incorrect references, inconsistencies, and gaps before proceeding to implementation planning.

## Skill Invocation

The skill is invoked via Claude Code slash command:

```
/reviewing-requirements <path-or-id>
```

### Arguments
- `<path-or-id>` (required) - Path to a requirement document, or a requirement ID (e.g., `FEAT-006`, `CHORE-003`, `BUG-001`)

### Behavior
- If a path is provided, use it directly
- If an ID is provided, resolve it by searching `requirements/features/`, `requirements/chores/`, `requirements/bugs/`, and `requirements/implementation/` for a file containing that ID
- If no match is found, display an error with the directories searched

### Examples
```
/reviewing-requirements requirements/features/FEAT-006-reviewing-requirements-skill.md
/reviewing-requirements FEAT-005
/reviewing-requirements CHORE-003
/reviewing-requirements BUG-001
```

## Functional Requirements

### FR-1: Document Parsing
- Read and parse the target requirement document
- Identify document type from ID prefix (FEAT, CHORE, BUG) or file location
- Extract all sections for analysis: functional requirements, acceptance criteria, edge cases, dependencies, references

### FR-2: Codebase Reference Verification
- Extract all file paths, function names, class names, and module references from the document
- Verify each reference exists in the current codebase using file reads and searches
- Report references that cannot be found, categorized as:
  - **Missing**: Referenced path/function does not exist
  - **Moved**: A likely match exists at a different location (suggest correction)
  - **Ambiguous**: Multiple potential matches found (list candidates)

### FR-3: Documentation Citation Verification
- Identify claims about framework behavior, library APIs, or external documentation
- Where possible, verify claims against available documentation (README files, doc comments, official docs in `references/` directories)
- Flag citations that cannot be verified or appear inaccurate

### FR-4: Internal Consistency Checks
- Verify that every functional requirement (FR-N) is covered by at least one acceptance criterion
- Verify that edge cases have corresponding handling described in FRs or NFRs
- Check for contradictions between sections (e.g., an edge case that conflicts with an FR)
- For bug reports: verify every root cause (RC-N) has a corresponding acceptance criterion
- For implementation plans: verify phase dependencies are consistent

### FR-5: Gap Analysis
- Identify missing error handling scenarios (referenced operations without failure modes)
- Flag untested paths (FRs without corresponding testing requirements)
- Detect unstated assumptions (implicit dependencies not listed in Dependencies section)
- Check for missing edge cases based on the feature's domain

### FR-6: Cross-Reference Validation
- Verify references to other requirement documents (e.g., "See FEAT-005") point to existing docs
- Verify GitHub issue references are valid (issue exists and is accessible)
- Check that referenced skills or workflow steps exist in the plugin

### FR-7: Findings Presentation
- Organize findings by severity:
  - **Error**: Incorrect references, broken paths, contradictions — must fix before proceeding
  - **Warning**: Potential gaps, unverifiable citations, ambiguous references — should review
  - **Info**: Suggestions for improvement, minor inconsistencies — nice to fix
- Display a summary count at the top (e.g., "Found 3 errors, 2 warnings, 1 info")
- Group findings by category (codebase refs, citations, consistency, gaps, cross-refs)
- Include the specific document section and line context for each finding

### FR-8: Fix Application
- After presenting findings, offer to apply fixes for issues that have clear corrections:
  - Update incorrect file paths to their actual locations
  - Fix stale cross-references to other requirement docs
  - Add missing coverage notes (e.g., add acceptance criteria for uncovered FRs)
- Require user approval before applying any changes
- Show a diff preview of proposed changes before applying

### FR-9: Document Type Support
- **Feature requirements** (`FEAT-*`): Full validation including FR/NFR coverage, acceptance criteria mapping, edge case analysis
- **Chore documents** (`CHORE-*`): Validate affected files, acceptance criteria, scope boundaries
- **Bug reports** (`BUG-*`): Validate root cause references (RC-N to acceptance criteria traceability), affected files, steps to reproduce
- **Implementation plans** (`FEAT-*` in `requirements/implementation/`): Validate phase dependencies, referenced files, status consistency

## Output Format

```
## Requirements Review: FEAT-006

### Summary
Found **3 errors**, **2 warnings**, **1 info** in FEAT-006-reviewing-requirements-skill.md

### Errors

**[E1] Codebase Reference — FR-2**
Referenced file `scripts/lib/validator.ts` does not exist.
Suggestion: Did you mean `scripts/lib/skill-utils.ts`?

**[E2] Internal Consistency — FR-4 / Acceptance Criteria**
FR-4 (Internal Consistency Checks) has no corresponding acceptance criterion.
Suggestion: Add "- [ ] Checks internal consistency across sections" to Acceptance Criteria.

**[E3] Cross-Reference — Dependencies**
Referenced requirement `FEAT-003` not found in `requirements/features/`.
Found: `requirements/features/FEAT-003-skill-allowed-tools.md` — reference is valid but imprecise.

### Warnings

**[W1] Gap — Error Handling**
FR-1 (Document Parsing) does not describe behavior when the document has malformed YAML frontmatter.
Suggestion: Add edge case for malformed/missing frontmatter.

**[W2] Citation — FR-3**
Claim "validate() API from ai-skills-manager" could not be verified against available documentation.
Consider: Add reference link or verify API name.

### Info

**[I1] Suggestion — Testing Requirements**
No integration test scenario for cross-reference validation (FR-6).
Consider: Add test case for validating references to other requirement docs.

---
Would you like me to apply the suggested fixes? (Errors E1, E2 will be applied; E3 needs manual review)
```

## Non-Functional Requirements

### NFR-1: Performance
- Complete review of a typical requirement document (< 500 lines) within a single interaction
- Codebase searches should use targeted glob/grep rather than exhaustive scans

### NFR-2: Error Handling
- Document not found: Display clear error with the paths searched
- Malformed document: Proceed with partial analysis, noting which sections could not be parsed
- Codebase search failures: Report as warnings rather than blocking the review

### NFR-3: Non-Destructive
- Never modify the requirement document without explicit user approval
- Show diff previews before any changes
- Support a review-only mode (default) that only reports findings

## Dependencies

- `ai-skills-manager` validation API (for skill metadata validation)
- Existing requirement document templates (feature, chore, bug formats)
- Access to codebase for reference verification (Glob, Grep, Read tools)
- GitHub CLI (`gh`) for issue reference validation

## Edge Cases

1. **Document has no codebase references**: Skip FR-2, report as info ("No codebase references found to verify")
2. **Document is an implementation plan**: Adapt checks to validate phase structure, status markers, and phase dependencies instead of FR/NFR format
3. **Referenced GitHub issue is in a different repo**: Note the cross-repo reference, attempt validation if accessible
4. **Document uses non-standard format**: Warn about format deviations but attempt partial analysis
5. **Requirement ID resolves to multiple files**: Display all matches and ask user to specify
6. **Empty or stub document**: Report as error with guidance to complete the document first
7. **Circular cross-references between documents**: Detect and report without infinite loops

## Testing Requirements

### Unit Tests
- ID-to-path resolution logic for each document type (FEAT, CHORE, BUG)
- Severity classification of findings
- Finding deduplication (same issue found via multiple checks)

### Integration Tests
- End-to-end review of a sample feature requirement document
- End-to-end review of a sample bug report
- End-to-end review of a sample implementation plan
- Fix application with diff preview

### Manual Testing
- Review a document with known errors and verify all are caught
- Review a clean document and verify no false positives
- Test fix application workflow with user approval
- Test with each document type (FEAT, CHORE, BUG, implementation plan)

## Workflow Integration

### Position in SDLC
```
documenting-* → reviewing-requirements → creating-implementation-plans → implementing-plan-phases → documenting-qa → executing-qa
```

### Documenting Skill Updates
Each `documenting-*` skill should add a closing recommendation:
> *"Consider running `/reviewing-requirements` to verify this document against the codebase and docs before proceeding."*

Skills to update:
- `documenting-features`
- `documenting-chores`
- `documenting-bugs`

## Future Enhancements

- Auto-run review as part of `documenting-*` skill completion (opt-in)
- Severity threshold configuration (e.g., fail on errors only, or also on warnings)
- Review history tracking (store previous review results for comparison)
- Batch review mode (review all requirement docs in a directory)

## Acceptance Criteria

- [ ] `reviewing-requirements` skill exists in `plugins/lwndev-sdlc/skills/`
- [ ] Skill accepts a requirement document path or ID as input
- [ ] Resolves requirement IDs to file paths across all requirement directories
- [ ] Validates codebase references (files, functions, paths) with missing/moved/ambiguous classification
- [ ] Validates documentation citations where possible
- [ ] Checks internal consistency (FR-to-acceptance-criteria coverage, edge case alignment)
- [ ] Identifies gaps (missing error handling, untested paths, unstated assumptions)
- [ ] Validates cross-references to other requirement docs and GitHub issues
- [ ] Presents findings organized by severity (Error/Warning/Info) and category
- [ ] Offers to apply fixes with diff preview and user approval
- [ ] Works with FEAT, CHORE, BUG, and implementation plan documents
- [ ] Documenting skills updated with closing recommendation to run review
