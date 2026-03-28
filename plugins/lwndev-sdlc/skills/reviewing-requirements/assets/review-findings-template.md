# Requirements Review: {REQUIREMENT_ID}

<!-- Use the Standard Review format when no test plan exists, or the
     Test-Plan Reconciliation format when a test plan is found. -->

## Standard Review Format

### Summary
Found **{error_count} errors**, **{warning_count} warnings**, **{info_count} info** in {filename}

### Errors

**[E1] {Category} — {Section Reference}**
{Description of the issue.}
Suggestion: {Specific fix or correction.}

**[E2] {Category} — {Section Reference}**
{Description of the issue.}
Suggestion: {Specific fix or correction.}

### Warnings

**[W1] {Category} — {Section Reference}**
{Description of the issue.}
Consider: {Recommended action or review guidance.}

### Info

**[I1] {Category} — {Section Reference}**
{Description of the issue.}
Consider: {Optional improvement suggestion.}

---

### Fix Summary

**Auto-fixable** ({count}):
- [E1] {Brief description} — will update {what changes}
- [E2] {Brief description} — will update {what changes}

**Requires manual review** ({count}):
- [W1] {Brief description} — {why it needs human judgment}

Would you like me to apply the auto-fixable corrections?

---

## Test-Plan Reconciliation Format

### Summary
Test-plan reconciliation for {REQUIREMENT_ID}: Found **{error_count} errors**, **{warning_count} warnings**, **{info_count} info**

<!-- Categories for reconciliation findings:
     1. Cross-Reference Consistency (Step R2)
     2. Drift / Backport Candidates (Step R3)
     3. Test Plan Coverage Gaps (Step R4)
     4. Inconsistencies (Step R5)
-->

### Errors

**[E1] Cross-Reference Consistency — {Traceability ID}**
{Description: e.g., test plan references FR-N that does not exist in requirements.}
Suggestion: {Remove the reference or add the missing requirement.}

**[E2] Inconsistencies — {Traceability ID}**
{Description: e.g., test plan expects behavior X but requirement specifies behavior Y.}
Suggestion: {Resolve by updating the requirement or the test plan entry.}

### Warnings

**[W1] Test Plan Coverage Gaps — {Traceability ID}**
{Description: e.g., FR-3 has no corresponding entry in the test plan's Code Path Verification.}
Consider: {Add a test plan entry for this requirement, or confirm it is covered implicitly.}

**[W2] Cross-Reference Consistency — {Traceability ID}**
{Description: e.g., acceptance criterion has no corresponding test plan entry.}
Consider: {Add a verification checklist item or code path entry in the test plan.}

### Info

**[I1] Drift / Backport Candidates — {Test Plan Section}**
{Description: e.g., test plan introduces edge case not present in requirements.}
Consider: {Add to Edge Cases section of {requirement file}. Post comment on #{issue_number} noting scope clarification.}
Target: {requirements document | GitHub issue | implementation plan}

---

### Update Summary

**Applicable updates** ({count}):
- [W1] {Brief description} — will add {what} to {which artifact}

**Requires manual review** ({count}):
- [E2] {Brief description} — {why it needs human judgment}
- [I1] {Brief description} — {why: e.g., requires judgment on whether to expand scope}

Would you like me to apply the applicable updates?
