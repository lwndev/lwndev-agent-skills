## Verification Checklist

Before marking the workflow complete:

### Common Checks (all chain types)
- [ ] All steps executed in the correct order per the chain's step sequence
- [ ] State file at `.sdlc/workflows/{ID}.json` reflects completion
- [ ] Artifacts exist for all completed steps
- [ ] Sub-skills were NOT modified — no `context: fork` added to their frontmatter
- [ ] Reconciliation steps (reviewing-requirements in test-plan mode) were not skipped — unless CHORE-031 skip conditions apply (bug/chore chains: step 2 skipped if `complexity == low`; step 4 skipped if `complexity == low`)
- [ ] Stop hook prevents premature stopping during in-progress steps

### Feature Chain Checks
- [ ] PR was created only after all phases completed (not per-phase)
- [ ] Plan-approval pause occurred at step 4
- [ ] Phase loop correctly iterated through all N phases

### Chore Chain Checks
- [ ] No plan-approval pause occurred (chore chains skip this)
- [ ] No phase loop was executed (chore chains have a fixed 8-step sequence)
- [ ] PR number was extracted from `executing-chores` output or detected via `gh pr list` fallback
- [ ] `set-pr` was called with the correct PR number and branch after step 5

### Bug Chain Checks
- [ ] No plan-approval pause occurred (bug chains skip this)
- [ ] No phase loop was executed (bug chains have a fixed 8-step sequence)
- [ ] PR number was extracted from `executing-bug-fixes` output or detected via `gh pr list` fallback
- [ ] `set-pr` was called with the correct PR number and branch after step 5
- [ ] RC-N traceability maintained through the chain (delegated to sub-skills)

### Managing Work Items Checks
- [ ] Issue reference extracted from requirements document at workflow start (FR-7)
- [ ] `phase-start` comment posted before each implementation phase (feature chain)
- [ ] `phase-completion` comment posted after each implementation phase (feature chain)
- [ ] `work-start` comment posted before executing-chores (chore chain)
- [ ] `work-complete` comment posted after executing-chores (chore chain)
- [ ] `bug-start` comment posted before executing-bug-fixes (bug chain)
- [ ] `bug-complete` comment posted after executing-bug-fixes (bug chain)
- [ ] PR body includes issue link via FR-6 (`Closes #N` or `PROJ-123`)
- [ ] All `managing-work-items` invocations gracefully skipped when no issue reference found

### Issue Tracking Verification

Issue tracking is supplementary (NFR-1) and must never block workflow progression, but the **reason** for a skipped invocation matters. After the workflow completes, confirm the observed state matches exactly one of the three cases below — and that the log line type (INFO vs WARNING) matches the case. A silent mismatch (e.g., no comments posted but no WARNING either, when `issueRef` was populated) indicates a mechanism-missing regression of BUG-009 and must be escalated.

- [ ] **Case A — invocation succeeded and posted a comment**: `issueRef` was populated from the requirements document, the orchestrator executed `gh issue comment` / Jira backend calls inline, and at least one lifecycle comment is visible on the linked issue. Verification command: `gh issue view <N> --comments` (or `acli jira workitem view --key PROJ-123` for Jira). Expected: `phase-start` + `phase-completion` per phase (feature), or `work-start` + `work-complete` (chore), or `bug-start` + `bug-complete` (bug), plus `Closes #N` / `PROJ-123` in the PR body.
- [ ] **Case B — gracefully skipped because `issueRef` is empty**: The requirements document has no `## GitHub Issue` section (or the section is empty). The orchestrator's conversation log contains exactly one `[info] No issue reference found in requirements document -- skipping issue tracking.` line and no lifecycle comments are expected. No WARNING-level log lines should appear for issue tracking in this case. This is the correct NFR-1 behavior.
- [ ] **Case C — skipped because the invocation mechanism failed**: `issueRef` was populated, but the orchestrator could not execute the invocation because of a mechanism failure (unreadable `managing-work-items/SKILL.md`, missing `gh`, unauthenticated `gh`, exhausted Jira tiered fallback, unreadable template file). The orchestrator's conversation log contains at least one `[warn]` line in the format documented in "Mechanism-Failure Logging" identifying which failure mode fired. The workflow still completes, but the WARNING line makes the silent-skip regression observable. Verify the warning message names the specific failure (e.g., `gh CLI not found on PATH`, `No Jira backend available`) and not the generic "No issue reference found" info message.

If the observed state cannot be classified into one of these three cases, treat it as a BUG-009 regression candidate and investigate the conversation log for silent skips.

## Relationship to Other Skills

This skill orchestrates all other skills in the lwndev-sdlc plugin:

```
Feature chain:
documenting-features → [managing-work-items: extract issueRef]
  → reviewing-requirements (standard) → creating-implementation-plans
  → PAUSE → documenting-qa → reviewing-requirements (test-plan)
  → [managing-work-items: phase-start] → implementing-plan-phases (×N) → [managing-work-items: phase-completion]
  → Create PR [managing-work-items: FR-6 issue link]
  → PAUSE → executing-qa → finalizing-workflow

Chore chain:
documenting-chores → [managing-work-items: extract issueRef]
  → reviewing-requirements (standard) → documenting-qa
  → reviewing-requirements (test-plan)
  → [managing-work-items: work-start] → executing-chores [managing-work-items: FR-6 issue link] → [managing-work-items: work-complete]
  → PAUSE → executing-qa → finalizing-workflow

Bug chain:
documenting-bugs → [managing-work-items: extract issueRef]
  → reviewing-requirements (standard) → documenting-qa
  → reviewing-requirements (test-plan)
  → [managing-work-items: bug-start] → executing-bug-fixes [managing-work-items: FR-6 issue link] → [managing-work-items: bug-complete]
  → PAUSE → executing-qa → finalizing-workflow
```

### Feature Chain Skills

| Task | Skill |
|------|-------|
| Document feature requirements | `documenting-features` (step 1, main) |
| Issue tracking (fetch, comments, PR link) | `managing-work-items` (after step 1, before/after phases, at PR creation) |
| Review requirements | `reviewing-requirements` (steps 2/6, fork) |
| Create implementation plan | `creating-implementation-plans` (step 3, fork) |
| Document QA test plan | `documenting-qa` (step 5, main) |
| Implement phases | `implementing-plan-phases` (steps 7…6+N, fork) |
| Execute QA verification | `executing-qa` (step 6+N+3, main) |
| Merge and finalize | `finalizing-workflow` (step 6+N+4, fork) |

### Chore Chain Skills

| Task | Skill |
|------|-------|
| Document chore requirements | `documenting-chores` (step 1, main) |
| Issue tracking (comments, PR link) | `managing-work-items` (after step 1, before/after step 5) |
| Review requirements | `reviewing-requirements` (steps 2/4, fork) |
| Document QA test plan | `documenting-qa` (step 3, main) |
| Execute chore implementation | `executing-chores` (step 5, fork) |
| Execute QA verification | `executing-qa` (step 7, main) |
| Merge and finalize | `finalizing-workflow` (step 8, fork) |

### Bug Chain Skills

| Task | Skill |
|------|-------|
| Document bug report | `documenting-bugs` (step 1, main) |
| Issue tracking (comments, PR link) | `managing-work-items` (after step 1, before/after step 5) |
| Review requirements | `reviewing-requirements` (steps 2/4, fork) |
| Document QA test plan | `documenting-qa` (step 3, main) |
| Execute bug fix | `executing-bug-fixes` (step 5, fork) |
| Execute QA verification | `executing-qa` (step 7, main) |
| Merge and finalize | `finalizing-workflow` (step 8, fork) |
