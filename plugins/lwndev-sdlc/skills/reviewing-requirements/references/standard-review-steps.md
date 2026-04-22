# Standard Review — Steps 3-7 Detail

Deep procedural narrative for the standard-review check sequence. SKILL.md retains the dispatch entries (`### Step 3` through `### Step 7`) and points here for full guidance.

## Step 3: Codebase Reference Verification

For each reference extracted in Step 2, use targeted searches (not exhaustive scans). Parallelize independent searches with the Agent tool when many references exist.

- **File paths**: Glob to check existence. If not found, search `**/{basename}` — classify as **Moved** (likely match found) or **Missing** (no match).
- **Function/class names**: Grep for the definition. Classify as **Moved** (found in different file), **Ambiguous** (multiple locations), or **Missing**.
- **Module/package refs**: Check `package.json` for npm packages; verify import paths exist for internal modules.

## Step 4: Documentation Citation Verification

For external claims about framework/library APIs: search `node_modules/<specific-package>/` type definitions, project READMEs, and `references/` directories. For behavior claims, verify against locally available documentation. Classify unverifiable claims as **Warning** (not Error). Do not fetch external URLs.

## Step 5: Internal Consistency Checks

**All types**: acceptance criteria must be testable; dependencies must match what's referenced; edge cases must have handling described elsewhere.

**FEAT**: FR-N <-> acceptance criteria bidirectional coverage; edge cases must not contradict FRs; output format consistent with FRs; command syntax/invocation matches FRs.

**BUG**: RC-N <-> acceptance criteria bidirectional coverage (with `(RC-N)` tags); steps to reproduce consistent with root causes; affected files align with RC locations.

**CHORE**: scope boundaries clear; affected files exist in codebase (verify via Glob).

**Implementation plans**: phase dependencies consistent (no circular refs); status markers valid (`Pending`/`🔄 In Progress`/`✅ Complete`); deliverable paths plausible; "Depends on Phase N" references valid earlier phases.

## Step 6: Gap Analysis

Identify what's missing: operations without error handling in Edge Cases/NFRs; FR-N entries without corresponding test cases; dependencies used but not listed; configuration/environment requirements not mentioned; implicit ordering constraints; common edge cases for the domain (empty input, boundary conditions, concurrent access, permission errors).

## Step 7: Cross-Reference Validation

- **Requirement docs**: Glob for referenced IDs in `requirements/` directories. **Error** if not found; **Info** if imprecise.
- **GitHub issues**: `gh issue view N --json state,title` (validate up to 5). **Warning** if not found or inaccessible.
- **Skill references**: Check skill directory exists under `plugins/lwndev-sdlc/skills/`. **Error** if not found.
