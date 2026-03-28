---
name: reviewing-requirements
description: Validates requirement documents against the codebase and docs. Operates in three modes - standard review (before QA), test-plan reconciliation (after QA), and code-review reconciliation (after PR review). Use when the user says "review requirements", "validate requirements", "check requirements", or wants to verify a requirement document.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
argument-hint: <requirements-file>
---

# Reviewing Requirements

Validate requirement documents against the codebase and documentation. Operates in three modes:

- **Standard review** — validates requirements before QA planning begins (the default)
- **Test-plan reconciliation** — validates bidirectional consistency between the QA test plan and upstream artifacts after QA planning
- **Code-review reconciliation** — advisory drift report after a PR has been reviewed, covering test plan staleness, GitHub issue updates, and requirements drift

## When to Use This Skill

- User says "review requirements", "validate requirements", or "check requirements"
- User provides a requirement document path or ID for review
- **Standard review**: After a `documenting-*` skill has produced a requirement document, before `documenting-qa`
- **Test-plan reconciliation**: After `documenting-qa` has produced a test plan, before execution (`implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`)
- **Code-review reconciliation**: After a PR has been reviewed and its findings addressed, before `executing-qa`

## Arguments

- **When argument is provided**: Match the argument against requirement files by ID prefix. Search across `requirements/features/`, `requirements/chores/`, and `requirements/bugs/` for a matching document (e.g., `FEAT-006` matches `FEAT-006-reviewing-requirements-skill.md`). If no match is found, inform the user and fall back to interactive selection. If multiple matches are found, present the options.
- **When no argument is provided**: Ask the user for a requirement document path or ID.

## Quick Start

1. Accept a requirement document path or ID (supports `--pr <number>` flag for code-review reconciliation)
2. Resolve to a file path if an ID was given
3. **Detect mode**: Check for PR → test plan → default to standard review
4. **If PR exists** → Code-review reconciliation: Run Steps CR1-CR5 (advisory drift report)
5. **If test plan exists (no PR)** → Test-plan reconciliation: Run Steps R1-R7
6. **If neither** → Standard review: Parse document, run Steps 3-7, present findings, offer fixes

## Input

The user provides either:

- **A file path**: `requirements/features/FEAT-006-reviewing-requirements-skill.md`
- **A requirement ID**: `FEAT-006`, `CHORE-003`, `BUG-001`

An optional `--pr <number>` flag can be appended to force code-review reconciliation mode with a specific PR (e.g., `/reviewing-requirements FEAT-007 --pr 85`).

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

## Step 1.5: Detect Review Mode

After resolving the requirement document, detect the mode in this order:

1. Extract the requirement ID (e.g., `FEAT-006`, `CHORE-022`, `BUG-001`)
2. **Check for a PR** (code-review reconciliation):
   - If `--pr <number>` was provided, use `gh pr view <number>` to load that PR. If the PR doesn't exist or the value is non-numeric, display an error and fall back to branch-based detection.
   - Otherwise, run `gh pr list --head <pattern> --json number,headRefName,state,isDraft` for patterns `feat/{ID}-*`, `chore/{ID}-*`, `fix/{ID}-*` (case-insensitive on the ID portion).
   - If multiple PRs match, use the most recently updated open PR. If no open PRs exist, list all matches and ask the user to specify.
   - If a PR is found → Enter **code-review reconciliation mode**. Proceed to [Code-Review Reconciliation Mode](#code-review-reconciliation-mode).
3. **Check for a test plan** (test-plan reconciliation):
   - Use Glob to check for `qa/test-plans/QA-plan-{ID}.md`
   - If found → Enter **test-plan reconciliation mode**. Proceed to [Test-Plan Reconciliation Mode](#test-plan-reconciliation-mode).
4. **Default** → Continue with **standard review** (Steps 2-9 below).

**Precedence**: If both a PR and a test plan exist, code-review reconciliation takes precedence (it is the later workflow step).

Display the detected mode:
```
Detected mode: Standard review (no test plan or PR found for {ID})
Hint: To run code-review reconciliation, use --pr <number> if a PR exists but branch naming doesn't match.
```
```
Detected mode: Test-plan reconciliation (found qa/test-plans/QA-plan-{ID}.md)
```
```
Detected mode: Code-review reconciliation (found PR #N from branch <branch-name>)
```
For draft PRs, display: `found Draft PR #N from branch <branch-name>`

| Mode | Trigger | Next Steps |
|------|---------|------------|
| Standard review | No PR, no test plan | Steps 2-9 |
| Test-plan reconciliation | Test plan exists, no PR | Steps R1-R7 |
| Code-review reconciliation | PR exists (with or without test plan) | Steps CR1-CR5 |

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

For each reference extracted in Step 2, use targeted searches (not exhaustive scans). Parallelize independent searches using the Agent tool when there are many references.

- **File paths**: Glob to check existence. If not found, search `**/{basename}` — classify as **Moved** (likely match found) or **Missing** (no match).
- **Function/class names**: Grep for the definition. Classify as **Moved** (found in different file), **Ambiguous** (multiple locations), or **Missing**.
- **Module/package refs**: Check `package.json` for npm packages; verify import paths exist for internal modules.

## Step 4: Documentation Citation Verification

For external claims about framework/library APIs: search `node_modules/<specific-package>/` type definitions, project READMEs, and `references/` directories. For behavior claims, verify against locally available documentation. Classify unverifiable claims as **Warning** (not Error). Do not fetch external URLs.

## Step 5: Internal Consistency Checks

**All types**: acceptance criteria must be testable; dependencies must match what's referenced; edge cases must have handling described elsewhere.

**FEAT**: FR-N ↔ acceptance criteria bidirectional coverage; edge cases must not contradict FRs; output format consistent with FRs; command syntax/invocation matches FRs.

**BUG**: RC-N ↔ acceptance criteria bidirectional coverage (with `(RC-N)` tags); steps to reproduce consistent with root causes; affected files align with RC locations.

**CHORE**: scope boundaries clear; affected files exist in codebase (verify via Glob).

**Implementation plans**: phase dependencies consistent (no circular refs); status markers valid (`Pending`/`🔄 In Progress`/`✅ Complete`); deliverable paths plausible; "Depends on Phase N" references valid earlier phases.

## Step 6: Gap Analysis

Identify what's missing: operations without error handling in Edge Cases/NFRs; FR-N entries without corresponding test cases; dependencies used but not listed; configuration/environment requirements not mentioned; implicit ordering constraints; common edge cases for the domain (empty input, boundary conditions, concurrent access, permission errors).

## Step 7: Cross-Reference Validation

- **Requirement docs**: Glob for referenced IDs in `requirements/` directories. **Error** if not found; **Info** if imprecise.
- **GitHub issues**: `gh issue view N --json state,title` (validate up to 5). **Warning** if not found or inaccessible.
- **Skill references**: Check skill directory exists under `plugins/lwndev-sdlc/skills/`. **Error** if not found.

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

## Test-Plan Reconciliation Mode

When a QA test plan exists for the requirement ID, validate bidirectional consistency between the test plan and the upstream requirement document.

### Step R1: Load Documents

Load the requirement document (already resolved), the QA test plan at `qa/test-plans/QA-plan-{ID}.md`, and the implementation plan if one exists. Extract all traceability IDs (FR-N, RC-N, NFR-N, acceptance criteria) from requirements, and all entries (Code Path Verification, New Test Analysis, Coverage Gap Analysis, Deliverable Verification, Verification Checklist) from the test plan.

### Step R2: Bidirectional Cross-Reference Check

Validate every traceability ID maps in both directions. **Requirements → Test Plan**: each FR-N, RC-N, AC must have at least one test plan entry. **Test Plan → Requirements**: each test plan reference must point to an existing requirement ID. Classify: **Error** if test plan references non-existent ID; **Warning** if a requirement has no test plan coverage.

### Step R3: Drift Detection

Find test plan entries introducing scenarios not in the original requirements — scan New Test Analysis, Coverage Gap Analysis, Code Path Verification, and Verification Checklist for content not traceable to any FR-N, RC-N, or AC. Classify as **Info** with label "Backport Candidate" and suggest which requirements section to update.

### Step R4: Reconciliation Gap Analysis

Check the external QA test plan (distinct from Step 6's inline testing check) against the requirement's traceability IDs: each FR-N/RC-N should have a Code Path Verification row; each AC should appear in Verification Checklist or Code Path Verification; each phase deliverable should appear in Deliverable Verification. Classify: **Warning** for missing coverage.

### Step R5: Inconsistency Detection

Compare test plan expectations against requirements: Code Path Verification descriptions vs. FR-N/RC-N; Deliverable Verification paths vs. requirements/implementation plan; New Test Analysis recommendations vs. requirements. Classify: **Error** for direct contradictions; **Warning** for ambiguous inconsistencies.

### Step R6: Present Reconciliation Findings

Use the same format as Step 8 with categories: Cross-Reference Consistency (R2), Drift/Backport Candidates (R3), Test Plan Coverage Gaps (R4), Inconsistencies (R5). Include actionable suggestions targeting specific artifacts (requirements doc, GitHub issue, implementation plan).

### Step R7: Offer Updates

Offer to apply clear corrections: backport candidates to Edge Cases/Acceptance Criteria, missing traceability references. Not auto-fixable: contradictions (design decisions), GitHub issue comments (user judgment), implementation plan changes (scope impact). Follow the same fix workflow as Step 9.

## Code-Review Reconciliation Mode

When a PR exists for the requirement ID, produce an advisory drift report. This mode covers areas that `executing-qa`'s reconciliation loop does not: test plan staleness, GitHub issue updates, and a preview of requirements-to-code drift.

**Scope boundary**: This mode is entirely advisory. It does NOT update affected files lists, modify implementation plan phases/deliverables/status, add deviation summaries, or auto-fix requirements documents. Those are handled by `executing-qa` reconciliation.

### Step CR1: Load PR Context

Fetch the PR diff using `gh pr diff <number>`. If `gh` is unavailable, fall back to `git diff <base-branch>...HEAD`. Load the requirement document (already resolved in Step 1). Load the test plan from `qa/test-plans/QA-plan-{ID}.md` if it exists — if not, skip CR2 and note as **Info** ("No test plan found; test plan staleness detection skipped"). If the PR diff is very large (> 100 changed files), warn the user and focus on files referenced in requirements and test plan. Fork PRs are supported — `gh pr diff` works normally for PRs from forks.

### Step CR2: Test Plan Staleness Detection

Compare test plan entries (Code Path Verification, New Test Analysis, Coverage Gap Analysis) against the PR diff. Flag entries referencing:
- **Changed function signatures or APIs** — parameter changes, renames, modified return types visible in the diff
- **Removed or renamed files** — test entries referencing files deleted or renamed in the PR
- **Modified behavior** — test entries whose "Expected Code Path" or "Description" describes behavior the diff alters

For each flagged entry, describe specifically what changed in the PR diff and how it affects the test plan entry. Classify: **Error** for entries that will definitely fail; **Warning** for entries that may verify the wrong thing.

### Step CR3: GitHub Issue Suggestions

Compare the PR diff and requirement document against the linked GitHub issue (from the requirement's "GitHub Issue" field). If no GitHub issue is linked, skip and note as **Info**. Produce draft suggestions for:
- **Scope changes** — behavior added or removed that differs from the original issue
- **Decisions made during review** — design choices or trade-offs resolved during code review
- **Deferred work** — items intentionally deferred to follow-up issues

Each suggestion includes a draft comment for user review. Never post or modify the issue directly.

### Step CR4: Advisory Requirements Drift Summary

Compare the PR diff against FR-N entries, acceptance criteria, and edge cases. Identify:
- FRs describing behavior not present in the diff (potentially unimplemented or changed)
- Diff changes introducing behavior not described in any FR (potentially undocumented)
- Acceptance criteria that may not hold given the actual implementation

Present as advisory only. Note that `executing-qa` reconciliation will handle actual document updates. Classify: **Warning** for drift findings; **Info** for minor discrepancies.

### Step CR5: Present Findings

Use the same severity classification and finding format as Step 8, with these categories:

1. **Test Plan Staleness** (CR2) — entries that may fail or verify the wrong thing
2. **GitHub Issue Suggestions** (CR3) — recommended issue updates
3. **Requirements ↔ Code Drift** (CR4) — advisory divergence preview

Display a summary count:
```
Code-review reconciliation for {ID} (PR #{N}): Found **N errors**, **N warnings**, **N info**
```

For findings that relate to `executing-qa`'s scope, note: "This drift will be addressed by `executing-qa` reconciliation."

## Document Type Adaptations

| Type | Adaptation |
|------|-----------|
| **FEAT** | Run all steps (1-9) — most comprehensive |
| **CHORE** | Skip Step 4 unless APIs referenced; emphasize Step 5 scope boundaries and Step 3 affected files |
| **BUG** | Emphasize RC-N ↔ AC traceability (Step 5); verify affected files (Step 3); check reproduction steps |
| **Implementation Plan** | Emphasize phase dependency consistency and status markers (Step 5); verify deliverable paths (Step 3); check feature requirement refs (Step 7) |

## Verification Checklist

### Standard Review

Before finishing a standard review, verify:

- [ ] Document was resolved and read successfully
- [ ] Document type was correctly identified
- [ ] Mode detection confirmed no test plan exists
- [ ] Codebase references were verified (file paths, functions, modules)
- [ ] Internal consistency was checked (type-appropriate checks applied)
- [ ] Gap analysis was performed
- [ ] Cross-references were validated
- [ ] Findings are organized by severity and category
- [ ] Summary count is accurate
- [ ] Fix suggestions are offered where applicable

### Test-Plan Reconciliation

Before finishing a reconciliation review, verify:

- [ ] Requirement document and test plan were both loaded successfully
- [ ] Mode detection confirmed test plan exists
- [ ] Bidirectional cross-references were validated (R2)
- [ ] Drift detection was performed and backport candidates identified (R3)
- [ ] Reconciliation gap analysis was performed against the test plan document (R4)
- [ ] Inconsistency detection compared test plan expectations against requirements (R5)
- [ ] Findings are organized by reconciliation category
- [ ] Findings include actionable suggestions targeting specific artifacts
- [ ] Summary count is accurate
- [ ] Update suggestions are offered where applicable

### Code-Review Reconciliation

Before finishing a code-review reconciliation, verify:

- [ ] PR detected and mode entered correctly (or `--pr` flag used)
- [ ] PR diff loaded (or `git diff` fallback used if `gh` unavailable)
- [ ] Test plan entries compared against PR diff (or skip noted if no test plan)
- [ ] GitHub issue suggestions produced (or skip noted if no issue linked)
- [ ] Advisory drift summary presented (no auto-fixes applied)
- [ ] Scope boundary respected (no `executing-qa` work duplicated)
- [ ] Findings organized by category with correct severity classification
- [ ] Summary count is accurate

## Relationship to Other Skills

This skill appears at multiple points in each workflow chain. The mode is automatic: PR exists → code-review reconciliation; test plan exists (no PR) → test-plan reconciliation; otherwise → standard review. Reconciliation steps are optional but recommended.

```
Features: documenting-features → reviewing-requirements (standard) → creating-implementation-plans → documenting-qa → reviewing-requirements (test-plan) → implementing-plan-phases → PR review → reviewing-requirements (code-review) → executing-qa → finalizing-workflow
Chores:   documenting-chores   → reviewing-requirements (standard) → documenting-qa → reviewing-requirements (test-plan) → executing-chores   → PR review → reviewing-requirements (code-review) → executing-qa → finalizing-workflow
Bugs:     documenting-bugs     → reviewing-requirements (standard) → documenting-qa → reviewing-requirements (test-plan) → executing-bug-fixes → PR review → reviewing-requirements (code-review) → executing-qa → finalizing-workflow
```

| Task | Recommended Approach |
|------|---------------------|
| Document requirements first | Use `documenting-features`, `documenting-chores`, or `documenting-bugs` |
| **Review requirements (before QA)** | **Use this skill — standard review mode** |
| Build QA test plan | Use `documenting-qa` |
| **Reconcile after QA plan creation** | **Use this skill — test-plan reconciliation mode (optional but recommended)** |
| Create implementation plan | Use `creating-implementation-plans` |
| Implement the plan | Use `implementing-plan-phases` |
| Execute chore or bug fix | Use `executing-chores` or `executing-bug-fixes` |
| **Reconcile after PR review** | **Use this skill — code-review reconciliation mode (optional but recommended)** |
| Execute QA verification | Use `executing-qa` |
| Merge PR and reset to main | Use `finalizing-workflow` |
