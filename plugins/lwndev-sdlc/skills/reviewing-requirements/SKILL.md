---
name: reviewing-requirements
description: Validates requirement documents against the codebase and docs. Use when the user says "review requirements", "validate requirements", "check requirements", or wants to verify a requirement document before implementation planning.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
---

# Reviewing Requirements

Validate requirement documents against the codebase and documentation after drafting. Catches incorrect references, internal inconsistencies, gaps, and stale cross-references before they propagate into implementation plans and code.

## When to Use This Skill

- User says "review requirements", "validate requirements", or "check requirements"
- User provides a requirement document path or ID for review
- After a `documenting-*` skill has produced a requirement document
- Before proceeding to `creating-implementation-plans`

## Quick Start

1. Accept a requirement document path or ID
2. Resolve to a file path if an ID was given
3. Parse the document and identify its type
4. Run verification checks (Steps 3-7)
5. Present findings organized by severity
6. Offer to apply fixes with user approval

## Input

The user provides either:

- **A file path**: `requirements/features/FEAT-006-reviewing-requirements-skill.md`
- **A requirement ID**: `FEAT-006`, `CHORE-003`, `BUG-001`

If no input is provided, ask the user for a document path or requirement ID.

## Step 1: Resolve Document

If the user provided a file path, verify it exists and use it directly.

If the user provided a requirement ID, resolve it to a file path:

| ID Prefix | Type | Search Directories |
|-----------|------|--------------------|
| `FEAT-` | Feature | `requirements/features/`, `requirements/implementation/` |
| `CHORE-` | Chore | `requirements/chores/` |
| `BUG-` | Bug | `requirements/bugs/` |

Search for files matching the pattern `{PREFIX}-{NNN}*.md` in the appropriate directory using Glob.

**If the ID matches files in multiple directories** (e.g., a FEAT-XXX has both a feature doc and an implementation plan), review all matching documents together. The feature requirements document is the primary target; the implementation plan is reviewed as a secondary document.

**Self-referential documents**: If the resolved document describes this skill itself (e.g., FEAT-006), proceed normally but note in the summary that findings about missing references or gaps may reflect the document describing features not yet implemented rather than actual errors. Use **Info** severity for ambiguous cases.

**If no match is found**, display an error listing the directories searched:
```
No requirement document found for ID "FEAT-099".
Searched: requirements/features/, requirements/implementation/
```

## Step 2: Parse Document

Read the document and determine its type and structure.

### Identify Document Type

Determine the type from the ID prefix or file location:

| Type | Identifying Markers | Key Sections to Extract |
|------|---------------------|------------------------|
| **Feature** | `FEAT-` prefix, in `requirements/features/` | FR-N, NFR-N, Acceptance Criteria, Edge Cases, Dependencies, Output Format |
| **Chore** | `CHORE-` prefix, in `requirements/chores/` | Acceptance Criteria, Affected Files, Scope |
| **Bug** | `BUG-` prefix, in `requirements/bugs/` | RC-N (Root Causes), Acceptance Criteria, Affected Files, Steps to Reproduce |
| **Implementation Plan** | in `requirements/implementation/` | Phases, Deliverables, Phase Dependencies, Status markers |

### Extract References

While parsing, collect all items that need verification:
- **File paths**: Strings containing `/` that look like project paths — typically starting with a known directory (`plugins/`, `scripts/`, `requirements/`, `src/`) or containing a file extension (e.g., `scripts/lib/skill-utils.ts`, `plugins/lwndev-sdlc/skills/`). Exclude URL paths, severity labels like `Error/Warning/Info`, and prose that happens to contain slashes.
- **Function/class names**: Code identifiers referenced in requirements (e.g., `validate()`, `getSourcePlugins()`)
- **Cross-references**: References to other requirement IDs (e.g., "See FEAT-005", "Depends on CHORE-003")
- **GitHub references**: Issue/PR numbers (e.g., `#38`, `PR #40`)
- **External claims**: Assertions about framework behavior, library APIs, or tool capabilities

## Step 3: Codebase Reference Verification

For each file path, function name, and code reference extracted in Step 2:

### File Paths
1. Use Glob to check if the referenced path exists
2. If not found, search for similar filenames to suggest corrections:
   - Extract the basename and search with `**/{basename}`
   - If a likely match is found, classify as **Moved** with a suggestion
   - If no match, classify as **Missing**

### Function/Class Names
1. Use Grep to search for the function or class definition
2. If found in a different file than referenced, classify as **Moved**
3. If found in multiple locations, classify as **Ambiguous** and list candidates
4. If not found anywhere, classify as **Missing**

### Module/Package References
1. For npm package references, check `package.json` dependencies
2. For internal module references, verify the import path exists

**Important**: Use targeted searches, not exhaustive scans. Search for specific names in specific directories. Parallelize independent searches using the Agent tool when there are many references to verify.

## Step 4: Documentation Citation Verification

For each external claim or documentation citation found in Step 2:

1. **Framework/library API claims**: Search for the referenced API in:
   - `node_modules/<specific-package>/` type definitions when a specific package is named (e.g., search `node_modules/ai-skills-manager/` not all of `node_modules/`)
   - README files in the project
   - `references/` directories in relevant skills
2. **Behavior claims**: If the document asserts specific behavior of a tool, framework, or library, check if this can be verified against available documentation
3. **If verification is not possible** (e.g., external docs not available locally), classify as a **Warning** rather than an **Error**, noting that the claim could not be verified

Do not attempt to fetch external URLs or documentation sites. Only verify against locally available information.

## Step 5: Internal Consistency Checks

Run these checks based on document type:

### All Document Types
- Every acceptance criterion should be testable (not vague or subjective)
- Dependencies section should list items actually referenced in the document
- Edge cases should have corresponding handling described elsewhere in the document

### Feature Requirements (FEAT)
- Every FR-N should have at least one corresponding acceptance criterion
- Every acceptance criterion should trace back to at least one FR-N or NFR-N
- Edge cases should not contradict functional requirements
- Output format examples should be consistent with FR descriptions
- If Command Syntax / Skill Invocation is present, arguments and options should match what FRs describe

### Bug Reports (BUG)
- Every RC-N (Root Cause) should have at least one corresponding acceptance criterion with an `(RC-N)` tag
- Every acceptance criterion should reference at least one RC-N
- Steps to reproduce should be consistent with the root cause analysis
- Affected files should align with root cause locations

### Chore Documents (CHORE)
- Scope boundaries should be clear (what changes and what does not)
- Affected files should all exist in the codebase (verify via Glob)

### Implementation Plans
- Phase dependencies should be consistent (no circular deps, no referencing non-existent phases)
- Phase status markers should be valid (`Pending`, `🔄 In Progress`, or `✅ Complete`)
- Deliverable file paths should be plausible (consistent with project structure)
- If a phase says "Depends on Phase N", Phase N should exist and come earlier in the sequence

## Step 6: Gap Analysis

Look for what's missing from the document:

### Missing Error Handling
- For each operation described in FRs (file reads, API calls, user input), check that there's a corresponding error scenario in Edge Cases or NFRs
- Flag operations without failure mode coverage

### Untested Paths
- For each FR-N, check that Testing Requirements includes a relevant test case
- Flag FRs without corresponding test coverage

### Unstated Assumptions
- Identify dependencies that are used but not listed in the Dependencies section
- Identify configuration or environment requirements not mentioned
- Check for implicit ordering constraints not documented

### Missing Edge Cases
- Based on the feature domain, identify common edge cases not listed:
  - Empty input, null/undefined values
  - Boundary conditions (max/min values)
  - Concurrent access or race conditions (if applicable)
  - Permission/access errors

## Step 7: Cross-Reference Validation

### Requirement Document References
For each reference to another requirement document (e.g., "See FEAT-005", "Related to CHORE-003"):
1. Use Glob to search for matching files in `requirements/features/`, `requirements/chores/`, `requirements/bugs/`, `requirements/implementation/`
2. If not found, classify as **Error**
3. If found but the reference is imprecise (e.g., says "FEAT-003" but file is `FEAT-003-skill-allowed-tools.md`), classify as **Info** suggesting a more precise reference

### GitHub Issue References
For each `#N` reference (validate up to 5; if more exist, note the remainder as unchecked to avoid API rate limits):
1. Use `gh issue view N --json state,title` to verify the issue exists
2. If the command fails or issue is not found, classify as **Warning** (the issue may be in a different repo or inaccessible)
3. If the issue exists, optionally verify its title aligns with the context

### Skill/Workflow References
For references to other skills (e.g., "use `documenting-features` skill"):
1. Check that the skill directory exists under `plugins/lwndev-sdlc/skills/`
2. If not found, classify as **Error**

## Step 8: Present Findings

Use the template from [assets/review-findings-template.md](assets/review-findings-template.md) to format findings.

### Severity Classification

Classify each finding:

| Severity | Criteria | Action Required |
|----------|----------|-----------------|
| **Error** | Incorrect references, broken paths, contradictions, missing traceability | Must fix before proceeding |
| **Warning** | Potential gaps, unverifiable citations, ambiguous references | Should review |
| **Info** | Suggestions for improvement, minor inconsistencies, imprecise references | Nice to fix |

### Category Grouping

Group findings by the check that produced them:
1. **Codebase References** (Step 3)
2. **Documentation Citations** (Step 4)
3. **Internal Consistency** (Step 5)
4. **Gaps** (Step 6)
5. **Cross-References** (Step 7)

### Finding Format

Each finding includes:
- A severity-coded identifier: `[E1]`, `[W1]`, `[I1]` (numbered within each severity)
- Category and relevant section reference
- Description of the issue
- Suggestion or fix (if available)

### Summary

Display a summary count at the top:
```
Found **N errors**, **N warnings**, **N info** in <filename>
```

If there are zero findings:
```
No issues found in <filename>. The document looks ready for implementation planning.
```

## Step 9: Apply Fixes

After presenting findings, offer to apply fixes **only for findings that have clear, unambiguous corrections**:

### Auto-fixable Issues
- Incorrect file paths where the correct location was found (Moved classification)
- Missing acceptance criteria for uncovered FRs (can generate a checklist item)
- Stale cross-references where the correct document was located
- Imprecise references that can be made more specific

### Not Auto-fixable
- Missing error handling scenarios (requires domain judgment)
- Contradictions between sections (requires design decision)
- Gap analysis findings (requires understanding of intent)
- Unverifiable documentation citations (requires external verification)

### Fix Workflow
1. List which findings can be auto-fixed and which require manual review
2. Ask user: "Would you like me to apply the suggested fixes?"
3. If yes, show a diff preview of each change before applying
4. Apply changes using the Edit tool
5. After applying, re-run only the affected checks to verify the fixes didn't introduce new issues

**Never modify the document without explicit user approval.**

## Document Type Adaptations

### When Reviewing a Feature Requirement
Run all steps (1-9). This is the most comprehensive review.

### When Reviewing a Chore Document
- Skip Step 4 (Documentation Citation Verification) unless the chore references specific APIs
- Emphasize Step 5 scope boundary checks
- Emphasize Step 3 affected files verification

### When Reviewing a Bug Report
- Emphasize RC-N to acceptance criteria traceability (Step 5)
- Verify affected files exist and are plausible locations for the described bug (Step 3)
- Check that steps to reproduce are specific and complete (Step 5)

### When Reviewing an Implementation Plan
- Emphasize phase dependency consistency (Step 5)
- Verify deliverable paths are plausible (Step 3)
- Check for referenced feature requirements docs (Step 7)
- Verify status markers are valid (Step 5)

## Verification Checklist

Before finishing, verify:

- [ ] Document was resolved and read successfully
- [ ] Document type was correctly identified
- [ ] Codebase references were verified (file paths, functions, modules)
- [ ] Internal consistency was checked (type-appropriate checks applied)
- [ ] Gap analysis was performed
- [ ] Cross-references were validated
- [ ] Findings are organized by severity and category
- [ ] Summary count is accurate
- [ ] Fix suggestions are offered where applicable

## Relationship to Other Skills

```
documenting-* → reviewing-requirements → creating-implementation-plans → implementing-plan-phases → documenting-qa → executing-qa
```

| Task | Recommended Approach |
|------|---------------------|
| Document requirements first | Use `documenting-features`, `documenting-chores`, or `documenting-bugs` |
| **Review requirements** | **Use this skill (`reviewing-requirements`)** |
| Create implementation plan | Use `creating-implementation-plans` |
| Implement the plan | Use `implementing-plan-phases` |
| Build QA test plan | Use `documenting-qa` |
| Execute QA verification | Use `executing-qa` |
