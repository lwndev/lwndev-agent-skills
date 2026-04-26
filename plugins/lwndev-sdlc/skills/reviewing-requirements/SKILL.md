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

Validate requirement documents against the codebase and documentation. Three modes:

- **Standard review** — validates requirements before QA planning (the default)
- **Test-plan reconciliation** — validates bidirectional consistency between the QA test plan and upstream artifacts after QA planning
- **Code-review reconciliation** — advisory drift report after a PR has been reviewed (test plan staleness, GitHub issue updates, requirements drift)

## When to Use This Skill

- User says "review requirements", "validate requirements", or "check requirements"
- User provides a requirement document path or ID for review
- **Standard review**: After a `documenting-*` skill produces a requirement document, before `documenting-qa`
- **Test-plan reconciliation**: After `documenting-qa` produces a test plan, before execution (`implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`)
- **Code-review reconciliation**: After a PR has been reviewed and its findings addressed, before `executing-qa`

## Arguments

- **When argument is provided**: Match the argument against requirement files by ID prefix. Search `requirements/features/`, `requirements/chores/`, and `requirements/bugs/` (e.g., `FEAT-006` matches `FEAT-006-reviewing-requirements-skill.md`). If no match, inform the user and fall back to interactive selection. If multiple matches, present the options.
- **When no argument is provided**: Ask the user for a requirement document path or ID.

## Quick Start

1. Accept a requirement document path or ID (supports `--pr <number>` flag for code-review reconciliation)
2. Resolve to a file path if an ID was given
3. **Detect mode**: Check for PR -> test plan -> default to standard review
4. **If PR exists** -> Code-review reconciliation: Run Steps CR1-CR5 (advisory drift report)
5. **If test plan exists (no PR)** -> Test-plan reconciliation: Run Steps R1-R7
6. **If neither** -> Standard review: Parse document, run Steps 3-7, present findings, offer fixes

## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration. This skill's full findings block (Step 8 / R6 / CR5) is itself a load-bearing carve-out — it is the payload the orchestrator displays to the user before the findings-decision prompt and must never be truncated.

### Lite narration rules

- No preamble before tool calls. Do not announce "let me check" or "I'll run" -- issue the tool call.
- No end-of-turn summaries beyond one short sentence. Do not recap what the user can read from tool output.
- No emoji. ASCII punctuation only.
- No restating what the user just said.
- No status echoes that tools already show.
- Prefer ASCII arrows (`->`) and punctuation over Unicode alternatives in skill-authored prose. Existing Unicode em dashes in tables and reference docs are retained.
- Short sentences over paragraphs. Bullet lists over prose when listing more than two items.

### Load-bearing carve-outs (never strip)

The following MUST always be emitted even when they resemble narration:

- **Error messages from `fail` calls** -- users need the reason the skill halted.
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts.
- **Interactive prompts** -- any prompt that blocks the workflow and requires user input (e.g., the "Would you like me to apply the auto-fixable corrections?" prompt in Step 9 / R7).
- **Findings display from `reviewing-requirements`** -- load-bearing for THIS skill. The full findings block (severity-ordered, category-grouped, per-finding `[E1] / [W1] / [I1]` rows) is the payload that the orchestrator displays to the user before the findings-decision prompt. It MUST be emitted in full and MUST NEVER be truncated, collapsed, or summarized away — lite rules do not override it.
- **FR-14 console echo lines** -- audit-trail lines using the documented Unicode `→` emitter format; do not rewrite to ASCII.
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim.
- **User-visible state transitions** -- pause, advance, and resume announcements (at most one line each).

### Fork-to-orchestrator return contract

This skill is forked by `orchestrating-workflows` at three points in each chain (standard review, test-plan reconciliation, code-review reconciliation). It emits a **non-standard** return shape — the `done | artifact=... | <note>` shape used by other forked skills is NOT produced by this skill.

- **On success**: emit the full findings block (severity-ordered, category-grouped per Step 8 / R6 / CR5) followed by the canonical summary line as the **final line** of the response:

  ```
  Found **N errors**, **N warnings**, **N info**
  ```

  Or, when zero counts across all severities: `No issues found in <filename>. The document looks ready for implementation planning.` The orchestrator's Decision Flow parses this final line directly (not a `done | artifact=...` payload).
- **On failure**: emit `failed | <one-sentence reason>` as the final line (same shape as other forked skills).

**Precedence**: the return contract takes precedence over the lite rules when the two conflict. The summary line (`Found **N errors** ...` on success, `failed | <reason>` on failure) MUST be the LAST line of the response even though a load-bearing findings block precedes it. Lite rules govern the findings block and all other prose, but never override the final-line contract or the findings-display carve-out.

## Input

The user provides either:

- **A file path**: `requirements/features/FEAT-006-reviewing-requirements-skill.md`
- **A requirement ID**: `FEAT-006`, `CHORE-003`, `BUG-001`

An optional `--pr <number>` flag forces code-review reconciliation mode with a specific PR (e.g., `/reviewing-requirements FEAT-007 --pr 85`).

If no input is provided, ask the user for a document path or requirement ID.

## Step 1: Resolve Document

If the user provided a file path, verify it exists and use it directly. If they provided an ID, resolve via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh" "<ID>"`. The script maps `FEAT-`/`CHORE-`/`BUG-` to the right directory, globs `{ID}-*.md`, and prints the path. Exit codes: `0` exactly-one match; `1` zero matches; `2` multiple matches (list candidates, ask user); `3` malformed/missing ID.

For `FEAT-` IDs, additionally Glob `requirements/implementation/{ID}-*.md`. If an ID matches files in multiple directories, review all together — the feature doc is primary, the implementation plan secondary.

**Self-referential documents**: If the resolved document describes this skill itself (e.g., FEAT-006), proceed normally but note in the summary that findings may reflect features not yet implemented. Use **Info** severity for ambiguous cases.

## Step 1.5: Detect Review Mode

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/detect-review-mode.sh" "<ID>" [--pr <N>]`. Applies the mode precedence chain (explicit `--pr` > open PR via `gh` > test plan exists > standard) and emits `{"mode":"code-review","prNumber":<N>}`, `{"mode":"test-plan","testPlanPath":"..."}`, or `{"mode":"standard"}` on stdout. Exit codes: `0` on any recognized outcome; `1` on malformed `gh` JSON; `2` on missing/malformed args. Dispatch on the `mode` field and display it verbatim to the user (e.g., `Detected mode: Standard review`). See [FR-1 in FEAT-026](../../../../requirements/features/FEAT-026-reviewing-requirements-scripts.md) for the full spec.

| Mode | Trigger | Next Steps |
|------|---------|------------|
| Standard review | No PR, no test plan | Steps 2-9 |
| Test-plan reconciliation | Test plan exists, no PR | Steps R1-R7 |
| Code-review reconciliation | PR exists (with or without test plan) | Steps CR1-CR5 |

## Step 2: Extract References

Identify the document type from the table below (governs reasoning emphasis in later steps), then run the extraction script.

| Type | Identifying Markers | Key Sections to Extract |
|------|---------------------|------------------------|
| **Feature** | `FEAT-` prefix, in `requirements/features/` | FR-N, NFR-N, Acceptance Criteria, Edge Cases, Dependencies, Output Format |
| **Chore** | `CHORE-` prefix, in `requirements/chores/` | Acceptance Criteria, Affected Files, Scope |
| **Bug** | `BUG-` prefix, in `requirements/bugs/` | RC-N (Root Causes), Acceptance Criteria, Affected Files, Steps to Reproduce |
| **Implementation Plan** | in `requirements/implementation/` | Phases, Deliverables, Phase Dependencies, Status markers |

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/extract-references.sh" "<doc-path>"`. Scans the document for four reference classes and emits `{"filePaths":[...],"identifiers":[...],"crossRefs":[...],"ghRefs":[...]}` on stdout — all four arrays always present. Exit codes: `0` success; `1` file unreadable; `2` missing arg. Pass this JSON to `verify-references.sh` in Step 3. External claims (framework behavior, library APIs) are not in scope — handle those in Step 4. See [FR-2 in FEAT-026](../../../../requirements/features/FEAT-026-reviewing-requirements-scripts.md).

## Steps 3-7: Verification Checks

Run the standard-review check sequence in order. See [references/standard-review-steps.md](references/standard-review-steps.md) for Steps 4, 5, and 6 per-step procedure.

- **Step 3 — Codebase Reference Verification**: Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/verify-references.sh" "<refs-json-or-path>"`. Accepts the JSON from `extract-references.sh` (literal string or file path), classifies each reference, and emits `{"ok":[],"moved":[],"ambiguous":[],"missing":[],"unavailable":[]}` — each entry `{"category":"...","ref":"...","detail":"..."}`. Emits one `[info] verify-references: gh unavailable; <N> ghRefs marked unavailable.` to stderr when `gh` is down. Exit: `0` success (including graceful skip); `1` unparseable JSON; `2` missing arg. Severity: `moved`/`ambiguous`/`missing` -> **Error** for `filePaths`/`identifiers`/`crossRefs`; `missing` -> **Warning** for `ghRefs` (issue may be in a different repo or inaccessible); `unavailable` -> **Info**. See [FR-3 in FEAT-026](../../../../requirements/features/FEAT-026-reviewing-requirements-scripts.md).
- **Step 4 — Documentation Citation Verification**: Verify external claims against `node_modules/<package>/` types and local docs. Unverifiable -> **Warning** (never Error). No external URL fetches.
- **Step 5 — Internal Consistency Checks**: type-specific consistency (FEAT FR-N <-> AC bidirectional; BUG RC-N <-> AC; CHORE scope; Implementation plans phase deps + status markers).
- **Step 6 — Gap Analysis**: missing error handling, untested FR-N, undeclared deps, missing configuration/edge cases.
- **Step 7 — Cross-Reference Validation**: Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/cross-ref-check.sh" "<doc-path>"`. Extracts `FEAT-N`/`CHORE-N`/`BUG-N` refs and verifies each has exactly one match under `requirements/{features,chores,bugs}/`. Emits `{"ok":[],"ambiguous":[],"missing":[]}` — each entry `{"category":"crossRefs","ref":"FEAT-020","detail":"..."}`. Exit: `0` success; `1` file unreadable; `2` missing arg. Severity: `missing`/`ambiguous` -> **Error**. See [FR-4 in FEAT-026](../../../../requirements/features/FEAT-026-reviewing-requirements-scripts.md).

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

After presenting findings, offer to apply fixes **only for findings that have clear, unambiguous corrections**.

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

When a QA test plan exists for the requirement ID, validate bidirectional consistency between it and the upstream requirement document.

### Steps R1-R5: Bidirectional Matcher (script)

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/reconcile-test-plan.sh" "<req-doc>" "<plan-doc>"`. Parses the requirement doc (FR-N/NFR-N/RC-N headings + `## Acceptance Criteria`) and the test plan (version-2 `[P0|P1|P2]` prose or legacy `| RC- | AC- |` tables), runs the full bidirectional match, and emits `{"gaps":[],"contradictions":[],"surplus":[],"drift":[],"modeMismatch":[]}` — each entry `{"id":"FR-3","location":"req-doc|test-plan:<line>","detail":"..."}`. Exit: `0` success; `1` unreadable/unparseable input (missing `## Acceptance Criteria` or no scenario lines); `2` missing args. Severity for R6: `gaps`/`drift`/`modeMismatch` -> **Warning**, `contradictions` -> **Error**, `surplus` -> **Info** (Backport Candidate). See [FR-5 in FEAT-026](../../../../requirements/features/FEAT-026-reviewing-requirements-scripts.md).

> **NFR-6 cross-reference (FEAT-030)**: The canonical results-vs-requirements reconciliation engine is `bash "${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/qa-reconcile-delta.sh" "<results-doc>" "<requirements-doc>"`. It emits markdown for the QA artifact's `## Reconciliation Delta` section (`### Coverage beyond requirements`, `### Coverage gaps`, `### Summary` with `coverage-surplus: N` / `coverage-gap: N`). `reconcile-test-plan.sh` is retained for R1-R5 because its 5-class JSON output (`gaps`/`contradictions`/`surplus`/`drift`/`modeMismatch`) is the input shape R6 severity classification consumes; `qa-reconcile-delta.sh`'s coverage-surplus/coverage-gap pair does not cover R2 contradictions, R4 priority drift, or R5 mode mismatch. The two scripts have intentionally distinct contracts: `reconcile-test-plan.sh` covers req-doc <-> plan classification; `qa-reconcile-delta.sh` covers results-doc <-> requirements artifact rendering. Both share the bidirectional FR-N/NFR-N/AC parsing approach.

### Step R6: Present Reconciliation Findings

Use Step 8 format with categories: Cross-Reference Consistency (R2), Drift/Backport Candidates (R3), Test Plan Coverage Gaps (R4), Inconsistencies (R5). Include actionable suggestions targeting specific artifacts (requirements doc, GitHub issue, implementation plan).

### Step R7: Offer Updates

Offer corrections for backport candidates (Edge Cases/Acceptance Criteria) and missing traceability references. Not auto-fixable: contradictions, GitHub issue comments, implementation plan changes. Follow the Step 9 fix workflow.

## Code-Review Reconciliation Mode

When a PR exists for the requirement ID, produce an advisory drift report covering areas `executing-qa` does not: test plan staleness, GitHub issue updates, and requirements-to-code drift preview.

**Scope boundary**: Entirely advisory. Does NOT update affected files lists, modify implementation plan phases/deliverables/status, add deviation summaries, or auto-fix requirements documents — those are `executing-qa` reconciliation's responsibility.

### Steps CR1-CR2: PR Diff vs Test Plan (script)

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/pr-diff-vs-plan.sh" "<pr-number>" "<test-plan>"`. Fetches `gh pr diff <N>`, parses the unified diff for changed/deleted/renamed files and changed function/class signatures, cross-references against test-plan entries, and emits `{"flaggedFiles":[],"flaggedIdentifiers":[],"flaggedSignatures":[]}` — each entry `{"testPlanLine":<N>,"scenarioSnippet":"...","drift":"deleted|renamed|signature-changed|content-changed","detail":"..."}`. When `gh` is missing or `gh pr diff` fails, emits `[warn]` to stderr and exits `0` with empty stdout (graceful skip — note **Info** in CR5). Exit: `0` success (including graceful skip); `1` unreadable test-plan; `2` missing/non-integer args. Severity for CR5: `deleted`/`renamed`/`signature-changed` -> **Error**, `content-changed` -> **Warning**. If the test plan does not exist for the ID, skip and note **Info** "No test plan found; test plan staleness detection skipped". See [FR-6 in FEAT-026](../../../../requirements/features/FEAT-026-reviewing-requirements-scripts.md).

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

Use Step 8 severity/finding format with categories: **Test Plan Staleness** (CR2), **GitHub Issue Suggestions** (CR3), **Requirements ↔ Code Drift** (CR4). Summary line: `Code-review reconciliation for {ID} (PR #{N}): Found **N errors**, **N warnings**, **N info**`. For findings in `executing-qa`'s scope, note: "This drift will be addressed by `executing-qa` reconciliation."

## Document Type Adaptations

| Type | Adaptation |
|------|-----------|
| **FEAT** | Run all steps (1-9) — most comprehensive |
| **CHORE** | Skip Step 4 unless APIs referenced; emphasize Step 5 scope boundaries and Step 3 affected files |
| **BUG** | Emphasize RC-N <-> AC traceability (Step 5); verify affected files (Step 3); check reproduction steps |
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

This skill appears at multiple points in each workflow chain. The mode is automatic: PR exists -> code-review reconciliation; test plan exists (no PR) -> test-plan reconciliation; otherwise -> standard review. Reconciliation steps are optional but recommended.

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
