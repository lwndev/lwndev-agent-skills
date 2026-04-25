# Feature Requirements: Consolidate executing-qa scripted producers, agent replacement, and report-only enforcement

## Overview

Consolidates three overlapping issues (#187 scripted producers, #192 agent script replacement, #208 report-only enforcement) into one feature shipping the executing-qa contract, six new producer scripts, agent replacement, stop-hook diff guard, workflow-state QA findings persistence, and orchestrator parsing — all against the same files and the same data path (test-runner output → artifact → workflow-state findings → orchestrator).

## Feature ID

`FEAT-030`

## GitHub Issue

[#242](https://github.com/lwndev/lwndev-marketplace/issues/242)

## Priority

High — closes three open issues (#187, #192, #208), part of the #179 prose-to-script backlog, and removes a real correctness defect (#208: executing-qa silently edits production code to make failing tests pass, hiding bugs behind an artificially green verdict).

## User Story

As a workflow user running `executing-qa`, I want the skill to report findings without modifying production code, persist a structured findings block to workflow-state, and execute its mechanical work via tested scripts so that QA verdicts reflect real test outcomes, the orchestrator can act on them programmatically, and per-run token cost drops by ~2,350–3,450 tokens.

## Scope

### In scope

- `executing-qa` SKILL.md non-remediation rule (#208 scope item 1)
- Six new executing-qa scripts (#187 items 7.1–7.6):
  - `capability-report-diff.sh`
  - `check-branch-diff.sh`
  - `run-framework.sh`
  - `qa-reconcile-delta.sh` (single shared implementation; also satisfies #192 item 11.2)
  - `render-qa-results.sh`
  - `commit-qa-tests.sh`
- Agent replacement (#192 items 11.1, 11.2):
  - `qa-verify-coverage.sh` replaces or wraps the `qa-verifier` agent
  - `qa-reconciliation-agent` reference logic replaced by the shared `qa-reconcile-delta.sh`
- Stop-hook diff guard (#208 scope item 2): reject runs that edit files outside the framework's test root
- Workflow-state QA findings persistence (#208 scope item 3): `record-qa-findings` subcommand (or generalized `record-findings` accepting QA shape) persists `{verdict, passed, failed, errored, summary}`
- Orchestrator parsing (#208 scope item 4): `orchestrating-workflows` parses the QA return contract and calls the new state subcommand before advancing
- QA return contract (#208 scope item 5): documented final-message shape (e.g. `Verdict: ISSUES-FOUND | Passed: 15 | Failed: 3 | Errored: 0`)
- Bats coverage for every new script behavior
- Regression test against a known-buggy branch

### Out of scope

- `#191` — `extract-chore-metadata.sh` and `extract-bug-metadata.sh` for `executing-chores` / `executing-bug-fixes`. Different surface, no overlap with this work. Tracked separately.
- Other items from the #179 backlog beyond 7.1–7.6, 11.1, 11.2.
- Broader workflow-state or orchestrator refactors not needed for QA findings persistence.

## Functional Requirements

### FR-1: Contract lock (precedes all producer code)

Document the QA return contract before any producer script lands. The contract has three parts:

1. **Artifact schema** — frontmatter fields (`id`, `version: 2`, `timestamp`, `verdict`, `persona`) and required sections (`## Summary`, `## Capability Report`, `## Execution Results`, `## Scenarios Run`, `## Findings`, `## Reconciliation Delta`, `## Exploratory Mode` for EXPLORATORY-ONLY). Already enforced by the existing stop-hook; this requirement only formalizes it as the contract producers must satisfy.
2. **Final-message line** — single line the orchestrator parses for verdict and counts:
   ```
   Verdict: <PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY> | Passed: <N> | Failed: <N> | Errored: <N>
   ```
   Emitted as the **final line** of the executing-qa skill's response (analogous to the fork-to-orchestrator return contract used elsewhere). For EXPLORATORY-ONLY the counts are `Passed: 0 | Failed: 0 | Errored: 0`.
3. **Workflow-state findings JSON shape**:
   ```json
   {
     "verdict": "PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY",
     "passed": <int>,
     "failed": <int>,
     "errored": <int>,
     "summary": "<one-line summary, e.g. '3 failing tests in state-transitions dimension; see qa/test-results/QA-results-FEAT-030.md'>"
   }
   ```
   Persisted on the QA step entry by the new `record-qa-findings` subcommand (or generalized `record-findings`).

The contract document lives under `plugins/lwndev-sdlc/skills/executing-qa/references/qa-return-contract.md` and is referenced by SKILL.md, the stop-hook, and the orchestrator.

### FR-2: Non-remediation rule in `executing-qa` SKILL.md

Add an explicit, unambiguous prohibition to `executing-qa` SKILL.md:

> Do not edit production code to make tests pass. Adversarial QA reports; it does not patch. If a finding suggests a fix, name the fix in `## Findings` and let `executing-bug-fixes` / `executing-chores` handle it in a follow-up run.

The rule appears prominently (top of the skill body or in a dedicated `## Report-Only Mode` section) and is referenced from the verdict-derivation step (Step 4) and the verification checklist.

### FR-3: `capability-report-diff.sh` (issue #187 item 7.1)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/capability-report-diff.sh" <plan-file> <fresh-json>
```

Compares the capability report embedded in the plan's frontmatter to a fresh capability JSON. Emits stdout JSON: `{drift: bool, fields: [{field, planValue, freshValue}]}`. Replaces the Step 1 drift note prose. Exit codes: `0` success; `2` missing/invalid args.

### FR-4: `check-branch-diff.sh` (issue #187 item 7.2)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/check-branch-diff.sh"
```

Runs `git diff main...HEAD`. Replaces edge case 5 (clean branch vs. main → ERROR). Exit codes: `0` non-empty diff; `1` empty diff (caller emits ERROR verdict).

### FR-5: `run-framework.sh` (issue #187 item 7.3)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/run-framework.sh" <capability-json> <test-file-glob>
```

Runs the framework's `testCommand` with the supplied test files. Captures stdout, stderr, exit code, and wall-clock duration. Parses framework output and emits stdout JSON:

```json
{
  "total": <int>,
  "passed": <int>,
  "failed": <int>,
  "errored": <int>,
  "failingNames": ["<test-name>", ...],
  "truncatedOutput": "<first 2000 chars per failing test or 50 lines, whichever shorter>",
  "exitCode": <int>,
  "durationMs": <int>
}
```

Replaces Step 4 framework execution + result parse prose. Exit codes: `0` runner ran (parse counts may indicate failures); `1` runner could not start (caller emits ERROR); `2` missing/invalid args. Frameworks supported: vitest, jest, pytest, go test (matching the existing `capability-discovery.sh` set).

### FR-6: `qa-reconcile-delta.sh` (issue #187 item 7.4 + #192 item 11.2 — single shared implementation)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/qa-reconcile-delta.sh" <results-doc> <requirements-doc>
```

Bidirectional FR-N / NFR-N / AC / edge-case parsing on both sides; matches by substring + identifier; emits the markdown for the `## Reconciliation Delta` section (including `### Coverage beyond requirements`, `### Coverage gaps`, and `### Summary` with `coverage-surplus: N` / `coverage-gap: N` lines). Exit codes: `0` delta produced; `1` requirements doc not found (caller emits skip-with-reason); `2` missing/invalid args.

This is the **single implementation** shared between `executing-qa` Step 6 and `reviewing-requirements` test-plan reconciliation mode (#179 item 3.6). The script lives under `executing-qa/scripts/` and `reviewing-requirements` invokes the same path. The `qa-reconciliation-agent.md` reference spec becomes the script's behavioral test matrix.

### FR-7: `render-qa-results.sh` (issue #187 item 7.5)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/render-qa-results.sh" <ID> <verdict> <capability-json> <execution-json>
```

Writes `qa/test-results/QA-results-{ID}.md` with the contract's frontmatter and required sections. Satisfies the per-verdict structural rules by construction (`Failed: 0` for PASS, failing-test names for ISSUES-FOUND, stack trace passthrough for ERROR, `Reason:` line for EXPLORATORY-ONLY). Replaces Step 7 emission prose. Exit codes: `0` artifact written; `1` invalid verdict / missing required field; `2` missing/invalid args.

### FR-8: `commit-qa-tests.sh` (issue #187 item 7.6)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/commit-qa-tests.sh" <ID> <test-files...>
```

Stages and commits the written test files with the canonical message `qa({ID}): add executable QA tests from executing-qa run`. Replaces Step 4 commit prose. Exit codes: `0` committed; `1` no files to commit; `2` missing/invalid args.

### FR-9: `qa-verify-coverage.sh` replaces the `qa-verifier` agent (issue #192 item 11.1)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/qa-verify-coverage.sh" <artifact-path>
```

Parses scenarios per dimension; validates priority (`P0|P1|P2`) and execution mode (`test-framework|exploratory`); checks the empty-findings directive (FR-6, FR-8 of QA reference); checks no-spec drift (`FR-\d+` / `AC-\d+` / `NFR-\d+` tokens in plan `## Scenarios`). Emits stdout JSON:

```json
{
  "verdict": "COVERAGE-ADEQUATE|COVERAGE-GAPS",
  "perDimension": [{"dimension": "<name>", "status": "covered|justified|missing", "scenarioCount": <int>}],
  "gaps": ["<specific gap>", ...]
}
```

The agent reference spec becomes the script's bats test matrix.

**Implementation choice** (deferred to plan time): delete `agents/qa-verifier.md` and `agents/qa-reconciliation-agent.md` entirely OR keep them as thin wrappers that shell out to the scripts. The plan phase decides; both options satisfy this FR.

### FR-10: Stop-hook diff guard (issue #208 scope item 2)

Extend `executing-qa/scripts/stop-hook.sh` to fail the run when `git status --porcelain` shows modifications outside the framework's test root. The framework test root is derived from the capability JSON (e.g., `__tests__/`, `tests/`, `*_test.go` patterns).

Behavior:
- Pure additions inside the test root (new `qa-*.spec.ts`, `test_qa_*.py`, `qa_*_test.go` files): allowed.
- Modifications to existing test files inside the test root: allowed.
- **Any** edit to a file outside the test root: block with explicit error naming the file and the test root.

Exception: edits to `qa/test-results/QA-results-{ID}.md` and `qa/test-plans/QA-plan-{ID}.md` are always allowed (these are QA artifacts, not production code).

Error message format:
```
Stop hook: executing-qa modified production files outside the framework test root '<test-root>': <file1>, <file2>. QA is report-only; do not edit production code to make tests pass. Revert these files and add the issue to ## Findings.
```

### FR-11: `record-qa-findings` subcommand on `workflow-state.sh` (issue #208 scope item 3)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh" record-qa-findings <ID> <stepIndex> <verdict> <passed> <failed> <errored> <summary>
```

Persists the QA findings block defined in FR-1 to the QA step entry in `.sdlc/workflows/{ID}.json`. Mirrors the existing `record-findings` shape (`reviewing-requirements` step records `{errors, warnings, info, decision, summary}`).

**Implementation choice** (deferred to plan time): new `record-qa-findings` subcommand OR generalize the existing `record-findings` to accept a QA shape via a `--type qa` flag. Both satisfy this FR. The plan phase decides.

Exit codes: `0` recorded; `1` workflow not found / step not a QA step; `2` missing/invalid args.

### FR-12: Orchestrator parses QA return contract (issue #208 scope item 4)

`orchestrating-workflows` SKILL.md (or its scripts) parses the FR-1 final-message line from the `executing-qa` main-context step output, extracts `{verdict, passed, failed, errored}`, derives a one-line `summary`, and calls `workflow-state.sh record-qa-findings` (or the generalized `record-findings --type qa`) **before** calling `advance`.

The QA step is a main-context step (not a fork), so the parse runs inline in the orchestrator's conversation immediately after the skill returns. The parse uses a fixed regex against the contract's exact format — failure to match is a `fail` with a contract-mismatch error.

The orchestrator does NOT change its advance behavior based on verdict — verdict-based gating (e.g., halt the workflow on ISSUES-FOUND) is out of scope and tracked separately. This FR only covers persistence.

### FR-13: SKILL.md adoption — every new script replaces prose in the same PR

`executing-qa` SKILL.md is rewritten so each of the six steps that newly has a script invokes the script and removes the equivalent prose. No script ships without a caller. The `## Quick Start` and verification checklist are updated to reference the scripts.

### FR-14: Documentation of the parse path in `orchestrating-workflows` SKILL.md

`orchestrating-workflows` SKILL.md adds a section (under `### Main-Context Steps` or `### Forked Steps` as appropriate) documenting how it parses the QA return contract from `executing-qa` and calls the new state subcommand. The exact regex / parser path lives in a script (FR-12) — SKILL.md describes the contract and points at the script.

## Output Format

### QA results artifact (unchanged frontmatter, new contract guarantee)

```markdown
---
id: FEAT-030
version: 2
timestamp: 2026-04-25T20:00:00Z
verdict: ISSUES-FOUND
persona: qa
---

## Summary
3 of 18 tests failed in the state-transitions dimension.

## Capability Report
[capability JSON or summary]

## Execution Results
- Total: 18
- Passed: 15
- Failed: 3
- Errored: 0
- Exit code: 1

## Scenarios Run
[...]

## Findings
- qa-state-transitions.spec.ts:42 — concurrent-cancel race surfaces partial commit
[...]

## Reconciliation Delta
[bidirectional surplus / gap]
```

### Final-message line (parsed by orchestrator)

```
Verdict: ISSUES-FOUND | Passed: 15 | Failed: 3 | Errored: 0
```

### Workflow-state JSON (QA step after FR-11 persistence)

```json
{
  "name": "Execute QA",
  "skill": "executing-qa",
  "context": "main",
  "status": "complete",
  "artifact": "qa/test-results/QA-results-FEAT-030.md",
  "completedAt": "2026-04-25T20:00:00Z",
  "findings": {
    "verdict": "ISSUES-FOUND",
    "passed": 15,
    "failed": 3,
    "errored": 0,
    "summary": "3 failing tests in state-transitions dimension; see qa/test-results/QA-results-FEAT-030.md"
  }
}
```

## Non-Functional Requirements

### NFR-1: Backwards compatibility

Existing FEAT-029 and earlier workflow state files (which lack the QA `findings` block) must continue to load. Resume of an in-progress pre-FEAT-030 workflow must not error on missing fields. The `findings` block is additive — its absence on older entries is allowed.

Existing `qa/test-results/QA-results-*.md` artifacts (version 2) remain valid; the contract changes only formalize what the stop-hook already enforces.

### NFR-2: Performance

Every new script must complete in under 1 second on a representative repo (excluding the framework `testCommand` execution itself, which is bound by the project's test suite). `qa-reconcile-delta.sh` parses two markdown documents and must complete in under 2 seconds for documents up to 5,000 lines combined.

### NFR-3: Error handling

- Each script emits actionable error messages on stderr; stdout is reserved for structured output (JSON or rendered markdown) per the script's contract.
- Exit codes follow the convention used elsewhere in the plugin (`0` success; `1` expected failure mode; `2` missing/invalid args; `3+` script-specific).
- Script failures inside `executing-qa` propagate verbatim to the user (lite-narration carve-out for error messages).

### NFR-4: Token cost

Per-workflow token cost for `executing-qa` drops by ~2,350–3,450 tokens (per #187 estimate, dominated by `qa-reconcile-delta.sh`). No regression in any other skill's token cost.

### NFR-5: Test coverage

Every new script behavior has a `bats` test alongside the script (per the project's "scripts over prose" convention). Coverage includes:
- Happy path
- Each documented exit code
- Edge cases the prose used to handle (empty diff, missing requirements doc, missing test directory, etc.)

The orchestrator's QA-contract parse path also has bats coverage (test fixture: a synthetic final-message line → expected `record-qa-findings` invocation).

### NFR-6: Single source of truth

`qa-reconcile-delta.sh` is **one** implementation called by both `executing-qa` Step 6 and `reviewing-requirements` test-plan reconciliation mode. No duplication.

## Dependencies

- Existing scripts: `capability-discovery.sh`, `persona-loader.sh`, `stop-hook.sh` (executing-qa); `workflow-state.sh`, `parse-findings.sh`, `findings-decision.sh` (orchestrating-workflows); `resolve-requirement-doc.sh` (plugin-shared).
- `bats-core` for script tests (already in use across the plugin).
- `gh` CLI (already required for the workflow).
- `jq` (already required by `workflow-state.sh`).

No new external dependencies.

## Edge Cases

1. **Empty branch diff** (FR-4): script exits 1; caller (`executing-qa` Step 4) emits ERROR verdict with `Reason: no changes to test relative to main` and skips writing tests.
2. **Missing requirements doc** (FR-6): `qa-reconcile-delta.sh` exits 1; caller emits `Reconciliation delta skipped: no requirements doc for {ID}` under `### Summary`.
3. **Capability drift between plan and fresh** (FR-3): script reports drift; caller updates the artifact's `## Capability Report` with the fresh values and notes the drift.
4. **Stop-hook diff guard false positive** — pre-existing uncommitted changes outside the test root: the diff guard checks against `git status --porcelain` filtered to **modifications since `executing-qa` started**, not all uncommitted changes. The skill writes a session marker (e.g., `.sdlc/qa/.executing-active` already exists; capture HEAD at start) and the stop-hook diffs against that baseline. **Implementation choice** (deferred to plan time): use `git stash` baseline, store HEAD in the marker, or compute the diff via `git diff <baseline-commit>`. The plan phase decides.
5. **Pre-existing test files modified by QA** — allowed (FR-10), since iterative test authoring is the skill's intended behavior.
6. **Generalized vs. dedicated `record-findings`** (FR-11): the plan phase chooses; if generalized, the existing `record-findings` callers (reviewing-requirements step) must continue to work unchanged.
7. **Agent-removal vs. agent-as-wrapper** (FR-9): the plan phase chooses; if removed, references in SKILL.md and other docs must be updated; if wrapped, the wrapper must keep the agent's existing tools/model frontmatter.
8. **Contract-mismatch on QA return** (FR-12): the orchestrator emits a `fail` with a contract-mismatch error, halts, and the user can re-invoke after fixing the artifact / final message.
9. **Multiple test runs in one session** — `executing-qa` is invoked once per workflow; not a multi-invocation skill. The session marker and findings persistence assume single invocation per workflow.
10. **Qa-tests already committed in a previous session** — `commit-qa-tests.sh` exits 1 with an info message; the skill continues without re-committing.

## Testing Requirements

### Unit Tests (bats)

Per script (FR-3 through FR-9, FR-11): test happy path, each documented exit code, and edge cases. New `*.bats` files alongside each script.

### Integration Tests

- **Regression test (acceptance criterion)**: run `executing-qa` against a known-buggy branch in a fixture repo. Verify:
  - Verdict is `ISSUES-FOUND`.
  - Findings list names the failing tests.
  - `git status` shows no modifications outside the framework's test root.
  - Workflow-state JSON contains the FR-1 `findings` block on the QA step.
  - Stop-hook does not block the run.

- **Negative regression test**: simulate the pre-FEAT-030 misbehavior (skill edits a production file). Verify the stop-hook diff guard blocks with the FR-10 error message.

- **Orchestrator parse test**: synthetic `executing-qa` final-message line → orchestrator parses → `record-qa-findings` invoked with correct args → workflow-state JSON updated correctly.

### Manual Testing

- Run a full feature workflow from `documenting-features` through `executing-qa` against a real codebase; verify the QA step output reads cleanly, the findings persist correctly, and no production files are touched.

## Acceptance Criteria

- [ ] Contract documented (FR-1: artifact schema + final-message format + workflow-state findings shape) before any producer code lands. (Equivalent to issue #242 AC #1.)
- [ ] `executing-qa/SKILL.md` contains an explicit, unambiguous prohibition on editing non-test source files during a QA run. (FR-2; issue #242 AC #2.)
- [ ] All six executing-qa scripts from #187 (FR-3 through FR-8) shipped and replacing the corresponding SKILL.md prose; every new script has at least one caller in `executing-qa` SKILL.md, and the Quick Start + verification checklist sections are updated to reference the scripts. (FR-13; issue #242 AC #3.)
- [ ] `qa-reconcile-delta.sh` is a single implementation shared by `executing-qa` and `reviewing-requirements` test-plan reconciliation mode. (FR-6, NFR-6; issue #242 AC #4.)
- [ ] `qa-verify-coverage.sh` replaces (or wraps) the `qa-verifier` agent; `qa-reconciliation-agent` reference logic is replaced by the shared `qa-reconcile-delta.sh`. (FR-9; issue #242 AC #5.)
- [ ] Stop hook fails the run when `git status` shows modifications outside the framework's test root. (FR-10; issue #242 AC #6.)
- [ ] `workflow-state.sh record-qa-findings` (or generalized `record-findings` accepting a QA shape) persists `{verdict, passed, failed, errored, summary}` to the QA step entry. (FR-11; issue #242 AC #7.)
- [ ] `orchestrating-workflows/SKILL.md` documents how it parses the QA return contract and calls the new state command. (FR-14; issue #242 AC #8.)
- [ ] `orchestrating-workflows` parses the `Verdict: <V> | Passed: <N> | Failed: <N> | Errored: <N>` line from `executing-qa` output and invokes `record-qa-findings` (or `record-findings --type qa`) **before** `advance`; a malformed final-message line halts the workflow with a contract-mismatch `fail`. (FR-12.)
- [ ] Bats coverage for every new script behavior, per the project's "scripts over prose" convention. (NFR-5; issue #242 AC #9.)
- [ ] Regression test: a QA run against a known-buggy branch produces an `ISSUES-FOUND` artifact, leaves non-test files untouched, and populates the workflow-state JSON correctly. (NFR-5; issue #242 AC #10.)
- [ ] Issues #187, #192, #208 closed by the merging PR via `Closes #N` lines.

## Packaging

Single feature, single `lwndev-sdlc` minor bump, single CHANGELOG entry, single revert point. #187, #192, #208 close on merge. Splitting into three PRs against the same files would produce merge-conflict churn and a half-built contract between merges (per issue #242 packaging rationale).

## Future Enhancements (out of scope)

- Verdict-based orchestrator gating (e.g., halt the workflow on ISSUES-FOUND, prompt the user). FR-12 only persists; gating is a separate feature.
- `executing-chores` / `executing-bug-fixes` metadata extractor scripts (#191 / #179 item 6.1, 6.2).
- Other items from #179 backlog beyond 7.1–7.6, 11.1, 11.2.

## Related

- Closes #187 (executing-qa: scripts)
- Closes #192 (Agents: qa-verifier + qa-reconciliation-agent — script replacement)
- Closes #208 (executing-qa should only report findings, never fix them)
- Part of #179 (prose-to-script backlog)
