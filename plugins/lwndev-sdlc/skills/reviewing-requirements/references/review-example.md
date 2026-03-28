# Standard Review Example

# Requirements Review: FEAT-006

## Summary
Found **3 errors**, **2 warnings**, **1 info** in FEAT-006-reviewing-requirements-skill.md

## Errors

**[E1] Codebase Reference — FR-2**
Referenced file `scripts/lib/validator.ts` does not exist.
Suggestion: Did you mean `scripts/lib/skill-utils.ts`?

**[E2] Internal Consistency — FR-4 / Acceptance Criteria**
FR-4 (Internal Consistency Checks) has no corresponding acceptance criterion.
Suggestion: Add "- [ ] Checks internal consistency across sections" to Acceptance Criteria.

**[E3] Cross-Reference — Dependencies**
Referenced requirement `FEAT-003` not found in `requirements/features/`.
Found: `requirements/features/FEAT-003-skill-allowed-tools.md` — reference is valid but imprecise.

## Warnings

**[W1] Gap — Error Handling**
FR-1 (Document Parsing) does not describe behavior when the document has malformed YAML frontmatter.
Consider: Add edge case for malformed/missing frontmatter.

**[W2] Citation — FR-3**
Claim "validate() API from ai-skills-manager" could not be verified against available documentation.
Consider: Add reference link or verify API name.

## Info

**[I1] Suggestion — Testing Requirements**
No integration test scenario for cross-reference validation (FR-6).
Consider: Add test case for validating references to other requirement docs.

---

### Fix Summary

**Auto-fixable** (2):
- [E1] Incorrect file path — will update `scripts/lib/validator.ts` to `scripts/lib/skill-utils.ts`
- [E2] Missing acceptance criterion — will add checklist item to Acceptance Criteria section

**Requires manual review** (1):
- [E3] Imprecise cross-reference — needs human judgment on whether to use full filename

Would you like me to apply the auto-fixable corrections?

---

# Test-Plan Reconciliation Example

# Requirements Review: CHORE-015

## Summary
Test-plan reconciliation for CHORE-015: Found **1 error**, **2 warnings**, **1 info**

## Errors

**[E1] Cross-Reference Consistency — AC-4**
Test plan Code Path Verification references "AC-4: Verify rollback on failure" but the CHORE-015 requirements document has only 3 acceptance criteria (AC-1 through AC-3).
Suggestion: Remove the AC-4 reference from the test plan, or add a 4th acceptance criterion to the requirements document if rollback verification is intended.

## Warnings

**[W1] Test Plan Coverage Gaps — AC-2**
AC-2 ("No existing tests are broken by the change") has no corresponding entry in the test plan's Code Path Verification table.
Consider: Add a Code Path Verification entry for AC-2 targeting the regression test suite.

**[W2] Cross-Reference Consistency — AC-3**
AC-3 ("Build succeeds after changes") appears in the Verification Checklist but has no Code Path Verification entry specifying which build step to verify.
Consider: Add a Code Path Verification row for AC-3 with the expected build command and success criteria.

## Info

**[I1] Drift / Backport Candidates — New Test Analysis**
Test plan recommends verifying that config file permissions are preserved after the change. This scenario is not present in the requirements document's acceptance criteria or notes.
Consider: Add "File permissions are preserved for modified config files" to the acceptance criteria in `requirements/chores/CHORE-015-correct-qa-workflow-placement.md`.
Target: requirements document

---

### Update Summary

**Applicable updates** (1):
- [E1] Stale AC-4 reference — will remove from test plan Code Path Verification table

**Requires manual review** (3):
- [W1] Missing test plan entry for AC-2 — requires judgment on what regression checks to specify
- [W2] Missing Code Path Verification for AC-3 — requires judgment on build verification specifics
- [I1] Backport candidate — requires judgment on whether to expand acceptance criteria scope

Would you like me to apply the applicable updates?
