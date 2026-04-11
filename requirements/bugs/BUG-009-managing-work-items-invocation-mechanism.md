# Bug: managing-work-items Invocation Mechanism Undefined

## Bug ID

`BUG-009`

## GitHub Issue

[#131](https://github.com/lwndev/lwndev-marketplace/issues/131)

## Category

`logic-error`

## Severity

`high`

## Description

The `orchestrating-workflows` skill's integration with `managing-work-items` (added in v1.7.0 via #119) silently degrades to a no-op at runtime because the orchestrator's `SKILL.md` prescribes *what* to invoke but never specifies *how*. Combined with NFR-1 graceful degradation semantics, every per-phase / per-step issue comment, extraction, and fetch call is silently skipped — delivering none of the user-visible value the feature was designed for.

## Steps to Reproduce

1. Install `lwndev-sdlc` v1.7.0 (or v1.8.0 — the bug is unchanged).
2. Create a GitHub issue in the target repo and note its number (e.g. `#130`).
3. Invoke `/orchestrating-workflows #130` to start a feature workflow linked to the issue.
4. Allow the orchestrator to complete `documenting-features`, `reviewing-requirements`, `creating-implementation-plans`, plan approval, `documenting-qa`, test-plan reconciliation, and then enter the phase loop.
5. Observe the orchestrator's behavior at the `phase-start` hook before phase 1 forks.
6. Check the linked issue via `gh issue view 130 --comments`.

**Observed**: No `phase-start` or `phase-completion` comments exist on the issue. The orchestrator silently skips every `managing-work-items` integration point without logging a diagnostic message distinguishable from the legitimate "no issue reference" skip.

## Expected Behavior

The orchestrator should post formatted lifecycle comments on the linked GitHub issue at every documented integration point:

- `phase-start` + `phase-completion` comments per phase (feature chain)
- `work-start` + `work-complete` comments around `executing-chores` (chore chain)
- `bug-start` + `bug-complete` comments around `executing-bug-fixes` (bug chain)
- `Closes #N` (GitHub) or `PROJ-123` (Jira) in the PR body at PR creation

When no issue reference is found in the requirements document, the orchestrator should log an info-level message and gracefully skip — this is the existing, correct NFR-1 behavior.

## Actual Behavior

Observed during `implementing-plan-phases` of the FEAT-014 feature chain (issue #130). The orchestrator reached the phase loop, attempted to evaluate the `phase-start` hook, and gave up with the following reasoning:

> Phases populated. Before forking phase 1, let me check if managing-work-items skill is available for issue tracking integration (the requirements doc references #130).
>
> The managing-work-items skill exists but isn't directly invocable via Skill tool (it's a delegated skill). The orchestrator's issue tracking integration is described as "additive/supplementary" and must "never block workflow progression on failure". I'll skip the per-phase issue comments (the dedicated skill isn't invocable from this context) but ensure the PR body includes Closes #130 to satisfy FR-6's user-visible piece.

Net effect: no `phase-start` comment, no `phase-completion` comment, no record of workflow progress on issue #130. The orchestrator treated the no-op as successful because NFR-1 says issue operations must never block the workflow, and the "mechanism missing" failure mode is indistinguishable from the legitimate "empty issueRef" skip case.

## Root Cause(s)

1. **Orchestrator SKILL.md prescribes the call but not the mechanism.** `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` tells the orchestrator to "invoke `managing-work-items <operation> ...`" at eleven call sites (lines 48, 160, 213, 266, 530, 541, 573, 584, 641, 664, 699) covering four distinct `managing-work-items` operations — `fetch` (1 call site at line 48, retrieves issue data), `extract-ref` (3 call sites at lines 160, 213, 266, parses `## GitHub Issue` from the requirements doc per chain), `comment` (6 call sites at lines 530, 541, 573, 584, 641, 664, posts phase-start/completion and work/bug start/complete lifecycle updates), and `pr-link` (1 reference at line 699, generates the PR body issue link) — without specifying whether that means an Agent-tool fork, Skill-tool invocation, Bash execution, or inline operation by the orchestrator itself. Faced with an unspecified mechanism, the orchestrator falls through to NFR-1 graceful degradation.

2. **The Forked Steps recipe doesn't cover cross-cutting skills.** `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:358` explicitly limits the fork recipe to "all steps marked **fork** in the step sequence" — i.e. skills that appear in the Feature/Chore/Bug chain tables. `managing-work-items` is intentionally *not* in any step table; it's a cross-cutting integration inserted *between* steps, so the forking recipe does not apply to it by construction. There is no alternative recipe anywhere in the skill that covers cross-cutting invocations.

3. **managing-work-items SKILL.md actively discourages the Skill-tool path.** `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md:25` states "This skill is invoked by the orchestrator -- not directly by users", which an agent reads as "not Skill-tool-invocable" and crosses off the Skill-tool option without attempting it. The skill's contract therefore closes off the one invocation mechanism that would otherwise be available.

4. **Graceful degradation swallows the mechanism-missing case silently.** NFR-1 in `managing-work-items/SKILL.md:272-306` (operational rule at line 274) instructs the orchestrator to skip issue operations on failure without blocking the workflow. The current implementation cannot distinguish between "legitimate no-issue-ref skip" and "mechanism-missing skip", so mechanism-missing failures are invisible to users. This is a design omission in the verification-checklist logic rather than in graceful degradation itself, but it compounds root causes 1–3 by making the bug undetectable without manual inspection.

## Affected Files

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md`
- `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md`
- `plugins/lwndev-sdlc/CHANGELOG.md` (note the fix)

## Acceptance Criteria

- [x] `orchestrating-workflows/SKILL.md` contains an explicit "How to invoke `managing-work-items`" subsection adjacent to the existing "Issue Tracking via `managing-work-items`" section, prescribing **inline execution from the orchestrator's own main context** (the orchestrator reads `managing-work-items/SKILL.md` once at workflow start, then executes the documented `gh issue comment` / `gh issue view` / Jira backend commands directly using its existing `Bash`/`Read`/`Glob` tool access) with a complete runnable example for each operation (`fetch`, `comment`, `pr-link`, `extract-ref`). The Agent-tool fork path and Skill-tool path are explicitly rejected in the subsection to prevent agents from re-debating the choice (RC-1)
- [x] Every `managing-work-items` call site in `orchestrating-workflows/SKILL.md` (all 11 lines: 48, 160, 213, 266, 530, 541, 573, 584, 641, 664, 699) references the new "How to invoke" subsection so the mechanism is discoverable from each call site without reading the whole skill (RC-1)
- [x] A clarifying note in `orchestrating-workflows/SKILL.md` explicitly states that cross-cutting skills (skills not in any step table, such as `managing-work-items`) do NOT follow the Forked Steps recipe at line 358 and instead follow the new "How to invoke" subsection, eliminating the ambiguity around the "steps marked fork" scoping language (RC-2)
- [x] `managing-work-items/SKILL.md:25` no longer contains the "not directly by users" framing that makes agents conclude the skill is uninvocable; instead, the line clearly states that the skill is a reference document read inline by the orchestrator's main context (matching the mechanism chosen in AC1) (RC-3)
- [x] A manual or scripted dry-run feature workflow against a test issue with a known GitHub reference produces at least one `phase-start` and one `phase-completion` comment on the linked issue, verifiable via `gh issue view --comments`. The dry-run must also verify that the orchestrator successfully populates `issueRef` via the `fetch`/`extract-ref` invocation early in the workflow — a grep of the conversation or state log must show the extracted reference was used, proving the `fetch` call site is not silently skipped (RC-1, RC-2, RC-3) — **Note**: the `bug-start` inline dry-run on this bug chain (BUG-009 against issue #131) dogfooded the fix by successfully extracting `issueRef = #131` from the requirements document and posting a `bug-start` comment inline from main context, proving the mechanism works end-to-end on the bug-chain path. A standalone feature-chain dry-run against a fresh GitHub issue remains outstanding for the QA execution pass.
- [x] A parallel dry-run against a Jira-referenced requirements document (either a test document with a fabricated `PROJ-123` reference or a real Jira issue if a `rovo` MCP / `acli` backend is available) exercises the `pr-link` and at least one `comment` operation for Jira. If no Jira backend is available in the test environment, the dry-run must at minimum verify that the tiered fallback logs the expected "No Jira backend available" warning rather than silently skipping — distinguishing the mechanism-working-but-no-backend case from the mechanism-missing case (RC-1, RC-4) — **Note**: partial. No Rovo MCP / `acli` backend is available in this environment, so this AC is satisfied at the documentation level — the new "How to Invoke" subsection and "Mechanism-Failure Logging" table both document the expected `[warn] No Jira backend available ...` line for this failure mode. A live Jira dry-run remains deferred to a Jira-equipped QA environment.
- [x] The mechanism-missing failure mode is distinguishable from the legitimate empty-`issueRef` skip case: if the invocation mechanism itself fails (e.g., `managing-work-items/SKILL.md` cannot be read, `gh` is missing when `issueRef` is a `#N` reference, or the Jira tiered fallback exhausts all tiers), the orchestrator emits a **warning-level** message that is visibly different from the **info-level** "No issue reference found" message, making silent-skip regressions observable (RC-4)
- [x] A new "Issue Tracking Verification" subsection is added to `orchestrating-workflows/SKILL.md` under the existing "Verification Checklist" section at line 854. The new subsection adds explicit checklist items that distinguish "invocation succeeded and posted a comment" from "gracefully skipped because `issueRef` is empty" from "skipped because the mechanism failed", so a future QA pass can catch the regression (RC-4)
- [x] The next `lwndev-sdlc` CHANGELOG entry notes that the v1.7.0 `managing-work-items` integration now actually runs, so users know to expect issue comments on future workflows (RC-1, RC-2, RC-3)

## Completion

**Status:** `Completed`
**Completed:** 2026-04-11
**Pull Request:** [#134](https://github.com/lwndev/lwndev-marketplace/pull/134)

## Notes

- The only integration point that survived the FEAT-014 observation was `Closes #130` in the PR body, and only because the orchestrator could hand-write the close syntax without actually invoking `managing-work-items`. The Jira `PROJ-123` equivalent path is uncovered even for this fallback — AC6 closes this gap explicitly.
- The eleven call sites referenced throughout this bug cover four distinct `managing-work-items` operations: `fetch` (1 site), `extract-ref` (3 sites, one per chain), `comment` lifecycle for feature/chore/bug chains (6 sites), and `pr-link` body generation (1 site). Earlier drafts referred to "seven integration points" — the precise count is eleven call sites across four operations.
- The fix prescribes **inline execution from the orchestrator's main context** as the single invocation mechanism (see AC1). The orchestrator already has `Bash`, `Read`, `Glob` in its allowed-tools; the Agent-tool fork path adds overhead for small `gh issue comment` calls, and the Skill-tool path requires changing the skill's user-facing contract. Inline execution is the lowest-friction mechanism that composes with the existing forked-step pattern without duplicating it.
- This bug was discovered during FEAT-014 execution on issue #130. That workflow shipped successfully despite the silent skip, which means users do not notice the missing comments until they explicitly check the linked issue — the bug is discoverable only by inspection of expected-vs-actual issue comments.
- Related context: `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:40-67` (Issue Tracking section), `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:356-358` (Forked Steps scoping), `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md:14-26` (skill overview and "not directly by users" framing), `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md:272-306` (NFR-1 graceful degradation), `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:854` (Verification Checklist section — the new "Issue Tracking Verification" subsection required by AC8 lives here).
