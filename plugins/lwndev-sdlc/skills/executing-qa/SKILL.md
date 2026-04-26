---
name: executing-qa
description: Executes adversarial QA against a feature branch by writing and running real tests (or producing a structured exploratory review when no test framework is detected). Emits a version-2 results artifact with verdict, execution results, findings, and reconciliation delta.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
hooks:
  Stop:
    - hooks:
        - type: command
          command: "${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/stop-hook.sh"
argument-hint: <requirement-id>
---

# Executing QA

Write and run adversarial tests against the change on the current branch. Grade the run on the framework's actual output. With no supported test framework detected, fall through to a structured exploratory review covering the five adversarial dimensions.

## Report-Only Mode

> Do not edit production code to make tests pass. Adversarial QA reports; it does not patch. If a finding suggests a fix, name the fix in `## Findings` and let `executing-bug-fixes` / `executing-chores` handle it in a follow-up run.

This rule is enforced by the FR-10 stop-hook diff guard (`scripts/stop-hook.sh`): edits outside the framework test root and outside `qa/test-results/` / `qa/test-plans/` block the run with a verbatim error. Verdict derivation in Step 4 cites this section. The Verification Checklist re-asserts it.

## When to Use This Skill

- After `documenting-qa` produces a v2 plan at `qa/test-plans/QA-plan-{ID}.md`
- Invoked by the orchestrator at feature step `5+N+3` / chore-bug step 6 (post-FEAT-018 chain-table numbering)
- Manually via `/executing-qa {ID}` against a checked-out feature branch

## Arguments

- **When argument is provided**: Match against requirement IDs by prefix. The prefix sets the type: `FEAT-` (feature), `CHORE-` (chore), `BUG-` (bug). Load the corresponding test plan from `qa/test-plans/QA-plan-{ID}.md`.
- **When no argument is provided**: Ask the user for a requirement ID.

## Quick Start

Script paths below are relative to `${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/` (abbreviated `$SCRIPTS/`).

1. Accept a requirement ID; record the active marker; record the diff baseline:
   - `Write .sdlc/qa/.executing-active`
   - `bash "$SCRIPTS/qa-baseline.sh" init <ID>`
2. Capability discovery + drift check:
   - `bash "$SCRIPTS/capability-discovery.sh" <consumer-root> <ID>`
   - `bash "$SCRIPTS/capability-report-diff.sh" "<plan-file>" "<fresh-json>"`
3. Load the v2 test plan; mode-route (test-framework or exploratory-only).
4. Pre-flight branch-diff check: `bash "$SCRIPTS/check-branch-diff.sh"`. Empty diff -> ERROR verdict path.
5. Test-framework mode:
   - Write tests under the framework's test root.
   - `bash "$SCRIPTS/run-framework.sh" <capability-json> "<test-glob>"`
   - `bash "$SCRIPTS/commit-qa-tests.sh" <ID> <test-files...>`
6. Build-health gate: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-build-health.sh" --no-interactive --skip-test`.
7. Reconciliation delta: `bash "$SCRIPTS/qa-reconcile-delta.sh" "<results-doc>" "<requirements-doc>"`.
8. Coverage check: `bash "$SCRIPTS/qa-verify-coverage.sh" "<artifact-path>"`.
9. Emit artifact: `bash "$SCRIPTS/render-qa-results.sh" <ID> <verdict> <capability-json> <execution-json>`.
10. Emit the FR-1 final-message line as the **last line** of the response.

## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration. This skill runs in the orchestrator's main conversation (feature chain step 5+N+3; chore/bug chain step 6), so its output flows directly to the user.

### Lite narration rules

- No preamble before tool calls. Do not announce "let me check" or "I'll run" -- issue the tool call.
- No end-of-turn summaries beyond one short sentence. Do not recap what the user can read from tool output (e.g., the written requirement document).
- No emoji. ASCII punctuation only.
- No restating what the user just said.
- No status echoes that tools already show (e.g., successful `Write` confirmations).
- Prefer ASCII arrows (`->`) and punctuation over Unicode alternatives in skill-authored prose. Existing Unicode em dashes in tables and reference docs are retained.
- Short sentences over paragraphs. Bullet lists over prose when listing more than two items.

### Load-bearing carve-outs (never strip)

The following MUST always be emitted even when they resemble narration:

- **Error messages from `fail` calls** -- users need the reason the skill halted. Surface script and tool stderr verbatim (`capability-discovery.sh`, `capability-report-diff.sh`, `check-branch-diff.sh`, `run-framework.sh`, `qa-reconcile-delta.sh`, `qa-verify-coverage.sh`, `render-qa-results.sh`, `commit-qa-tests.sh`, `qa-baseline.sh`, `persona-loader.sh`, `git diff`, `testCommand`) and the stop-hook block message when structural validation fails.
- **FR-2 non-remediation rule** -- the verbatim text in `## Report-Only Mode` is load-bearing; do not paraphrase, summarize, or omit when surfacing.
- **FR-10 stop-hook block message** -- emit verbatim:
  > Stop hook: executing-qa modified production files outside the framework test root '<test-root>': <file1>, <file2>. QA is report-only; do not edit production code to make tests pass. Revert these files and add the issue to ## Findings.
- **FR-1 final-message line** -- the `Verdict: <V> | Passed: <N> | Failed: <N> | Errored: <N>` line is the **last** line of the response (see [references/qa-return-contract.md](references/qa-return-contract.md)). The orchestrator parses this line via `parse-qa-return.sh`; any deviation triggers a contract-mismatch error.
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts.
- **Interactive prompts** -- any prompt that blocks the workflow and requires user input (e.g., the requirement ID prompt when no argument is provided, the missing-test-plan error pointing to `documenting-qa`, the pointer prompt when there are no branch changes to test).
- **Findings display from `reviewing-requirements`** -- N/A for this skill (it does not consume reviewing-requirements findings); bullet retained for consistency with the canonical template.
- **FR-14 console echo lines** -- `[model] step {N} ({skill}) -> {tier} (...)` audit-trail lines emitted by `prepare-fork.sh`. The Unicode `->` is the documented emitter format; do not rewrite to ASCII. (Typically not emitted here since this skill runs in main context, not forked, but retained for cross-skill consistency.)
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim.
- **User-visible state transitions** -- pause, advance, and resume announcements (at most one line each).

### Fork-to-orchestrator return contract

`executing-qa` runs in **main context** (feature chain step 5+N+3; chore/bug chain step 6), **not** as an Agent fork. It returns its result directly to the user, not to a parent orchestrator. The `done | artifact=<path> | <note>` / `failed | <reason>` shapes do **not** apply to this skill. Structural conformance of the artifact is enforced by the Stop hook at `scripts/stop-hook.sh`. The FR-1 final-message line is the orchestrator's parse target; it MUST be the last line of the response.

**Precedence**: when a load-bearing carve-out (error message, `[warn]` structured log, interactive prompt, the FR-2 rule body, the FR-1 final-message line) conflicts with a lite-narration rule, the carve-out wins and MUST be emitted verbatim.

## State File Management

At skill start:

1. Write `.sdlc/qa/.executing-active` (empty file). Signals the stop hook that `executing-qa` is active.
2. `bash "${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/qa-baseline.sh" init <ID>` writes `.sdlc/qa/.executing-qa-baseline-<ID>` with the current HEAD SHA. The FR-10 stop-hook diff guard reads this baseline to scope the diff check.

The stop hook removes both files on success; in orchestrated workflows the orchestrator cleans up after return. To clear the baseline manually: `bash "$SCRIPTS/qa-baseline.sh" clear <ID>`.

## Important: Bash-for-scripts-only

`Bash` is in `allowed-tools` so this skill can run the producer scripts above plus `git diff` and the framework's `testCommand`. Do NOT use Bash for output formatting, status messages, progress echoes, or `echo` statements. All user communication goes through direct response text, not shell `echo`.

## Input

The user provides a requirement ID in one of these formats:

- `FEAT-XXX` — Feature requirement
- `CHORE-XXX` — Chore / maintenance task
- `BUG-XXX` — Bug report

If no ID is provided, ask for one.

## Step 1: Capability discovery, baseline marker, persona

1. **Resolve the consumer repo root** via `git rev-parse --show-toplevel`.

2. **Initialize state**:
   - `Write .sdlc/qa/.executing-active` (empty file).
   - `bash ${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/qa-baseline.sh init <ID>` — writes the diff-guard baseline.

3. **Capability discovery**: if a fresh `/tmp/qa-capability-{ID}.json` from this session (mtime within the last hour) exists, reuse it. Otherwise:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/capability-discovery.sh <consumer-root> <ID>
   ```
   Capture the JSON. Fields: `mode` (`test-framework` | `exploratory-only`), `framework`, `packageManager`, `testCommand`, `language`. If `capability-discovery.sh` exits non-zero, treat as `mode: exploratory-only` with a recorded reason.

4. **Drift check** against the plan-embedded capability report:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/capability-report-diff.sh "<plan-file>" "<fresh-json>"
   ```
   Stdout JSON `{drift, fields}`. Drift JSON goes into the artifact's `## Capability Report` section verbatim; the fresh JSON is the source of truth for downstream steps.

5. **Compose the `qa` persona overlay**:
   ```
   source ${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/persona-loader.sh
   load_persona qa ${CLAUDE_PLUGIN_ROOT}/skills/executing-qa
   ```
   If `load_persona` returns non-zero, abort with the error — do not silently substitute a default.

## Step 2: Load the test plan

Read `qa/test-plans/QA-plan-{ID}.md`. If it does not exist, stop with:

> No test plan found at `qa/test-plans/QA-plan-{ID}.md`. Run `documenting-qa` first.

Validate `version: 2` in frontmatter. Reject `version: 1` with:

> Test plan is version 1 (pre-FEAT-018). Refusing to run the executable-oracle runner against a legacy closed-loop plan. Re-run `documenting-qa` to regenerate as version 2.

## Step 3: Mode selection

- `capability.mode == "test-framework"` -> Step 4.
- `capability.mode == "exploratory-only"` -> Step 5.

### Edge case 5: clean branch vs main -> ERROR

Before writing tests, the script wraps `git diff main...HEAD`:

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/check-branch-diff.sh
```

Exit `0` -> proceed. Exit `1` -> set verdict `ERROR` with `Reason: no changes to test relative to main`; jump to Step 6 (reconciliation delta) and Step 7 (emit artifact). Do not write tests; do not run the framework.

## Step 4: Test-framework mode -- write and run

For each P0/P1 scenario whose `mode: test-framework` marker is set:

1. **Write a test file** under the framework's test root with a `qa-` filename prefix. Defaults:
   - vitest / jest: `__tests__/qa-<dimension>.spec.ts` (or `.test.ts` per project config)
   - pytest: `tests/test_qa_<dimension>.py`
   - go test: `qa_<dimension>_test.go` next to the package under test

   Create the parent directory if absent (edge case 6). The skill prose still owns "what tests to write" (the scenario lines from the plan dictate the assertions).

2. **Run the framework** via the script:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/run-framework.sh <capability-json> "<test-glob>"
   ```
   Stdout JSON: `{total, passed, failed, errored, failingNames, truncatedOutput, exitCode, durationMs}`. Save the JSON to a temp file for downstream rendering.

3. **Commit the written test files**:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/commit-qa-tests.sh <ID> <test-files...>
   ```
   Exit `0` committed; exit `1` no files to commit (info; continue).

### Verdict derivation (test-framework mode)

Derive the verdict from the runner's actual JSON output -- never from self-report. See `## Report-Only Mode` for the no-remediation constraint.

- All written tests passed AND at least one scenario was exercised: `PASS`
- Any written test failed: `ISSUES-FOUND`
- Runner could not compile/parse the written tests: `ERROR`
- No tests were written because every scenario was `exploratory`: fall through to Step 5

### Edge case 3: compile errors -> ERROR, no retry

`run-framework.sh` exits 1 (or counts indicate the runner crashed). Verdict is `ERROR`; stack traces are passed through `truncatedOutput` and rendered into `## Findings` / `## Execution Results`. **Do not retry** and **do not patch the production code** (FR-2 / `## Report-Only Mode`) — the stop hook accepts a valid `ERROR` artifact as a complete run.

### Edge case 6: missing test directory

Create it. Normal for first-time QA runs on a fresh repo.

## Step 5: Exploratory-only mode

Produce a structured exploratory review. For each of the five adversarial dimensions, surface either at least one finding OR an explicit non-applicability justification. An empty dimension fails stop-hook validation.

Dimensions:
- **Inputs** — malformed, empty, boundary, encoding, excessive size, injection
- **State transitions** — cancellation, interruption, idempotency, concurrent invocations
- **Environment** — offline, low disk, slow network, wrong locale/timezone
- **Dependency failure** — external API 5xx/4xx/timeout, rate limiting, partial response
- **Cross-cutting** — accessibility, internationalization, concurrency, permissions

Populate the artifact's `## Exploratory Mode` section with a `Reason:` line. Set verdict to `EXPLORATORY-ONLY`. Counts in the FR-1 final-message line are `Passed: 0 | Failed: 0 | Errored: 0`.

## Step 5.5: Build-health gate (BUG-013)

After the test run but before the reconciliation delta:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-build-health.sh" --no-interactive --skip-test
```

`--skip-test` avoids re-running the suite. If the gate exits non-zero:

- Force the QA verdict to `ISSUES-FOUND`.
- Add a finding to `## Findings` describing the failing build-health stage with the failing command output excerpt — surfaced verbatim from the script's stderr.

## Step 6: Reconciliation Delta (FR-5 / FR-6)

Resolve the requirements-doc path:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh" "<ID>"
```

Exit `0` (path on stdout) -> run the delta. Exit `1` (zero matches) -> **edge case 7**: skip with reason. Exit `2` (ambiguous) -> warn; pick first alphabetically. Exit `3` -> malformed ID.

Then run the shared reconciler:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/qa-reconcile-delta.sh" "<results-doc>" "<requirements-doc>"
```

Stdout markdown for the artifact's `## Reconciliation Delta` section: `### Coverage beyond requirements`, `### Coverage gaps`, `### Summary` with `coverage-surplus: N` / `coverage-gap: N`.

Exit `0` delta produced. Exit `1` requirements doc not found at the supplied path (caller emits skip-with-reason). Exit `2` missing/invalid args.

### Edge case 7: missing requirements doc

If `resolve-requirement-doc.sh` exits 1 OR `qa-reconcile-delta.sh` exits 1, **skip** the reconciliation delta. Emit `Reconciliation delta skipped: no requirements doc for {ID}` under `## Reconciliation Delta` -> `### Summary` and continue. A missing spec is a different failure mode than an incorrect one.

## Step 6.5: Coverage verification (FR-9)

After the artifact is rendered, verify adversarial coverage:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/qa-verify-coverage.sh" "<artifact-path>"
```

Stdout JSON `{verdict, perDimension, gaps}` where `verdict` is `COVERAGE-ADEQUATE` or `COVERAGE-GAPS`. Coverage gaps are noted in `## Findings` but do not change the QA verdict. This script ships as the FR-9 producer for adversarial coverage verification (replaces the deleted Phase 3 reviewer agent).

## Step 7: Emit the version-2 results artifact

Render via the script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/render-qa-results.sh" <ID> <verdict> "<capability-json>" "<execution-json>"
```

Optional environment overrides for `## Findings`, `## Reconciliation Delta`, `## Scenarios Run`, `## Summary`, `## Exploratory Mode` are documented in the script header. The script writes `qa/test-results/QA-results-{ID}.md` per the Phase-1 contract ([references/qa-return-contract.md](references/qa-return-contract.md)) using the schema in [assets/test-results-template-v2.md](assets/test-results-template-v2.md).

Exit `0` artifact written. Exit `1` invalid verdict / missing required field. Exit `2` missing/invalid args.

The stop hook re-validates the artifact on disk.

## Step 8: Final message (FR-1)

State the verdict, the artifact path, and a 1-line run summary. Then emit the FR-1 final-message line as the **last** line of the response. Format ([references/qa-return-contract.md](references/qa-return-contract.md)):

```
Verdict: <PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY> | Passed: <int> | Failed: <int> | Errored: <int>
```

For `EXPLORATORY-ONLY`, the three counts are `0`. The orchestrator's `parse-qa-return.sh` matches this line with the canonical regex; any deviation is a contract-mismatch error.

## Verification Checklist

Before finishing, verify:

- [ ] `## Report-Only Mode` honored — no production-file edits outside the framework test root or `qa/test-results/` / `qa/test-plans/` (FR-2 / FR-10).
- [ ] `.sdlc/qa/.executing-active` written; `qa-baseline.sh init <ID>` ran.
- [ ] `capability-discovery.sh` produced the fresh JSON (or reused the cached `/tmp` copy).
- [ ] `capability-report-diff.sh` ran; drift recorded in `## Capability Report`.
- [ ] Persona overlay composed via `persona-loader.sh`.
- [ ] `check-branch-diff.sh` ran (Step 3 / edge case 5).
- [ ] Mode routed: test-framework -> `run-framework.sh` + `commit-qa-tests.sh`; exploratory-only -> all five dimensions covered.
- [ ] `qa-reconcile-delta.sh` produced the delta (or skipped per edge case 7).
- [ ] `qa-verify-coverage.sh` ran against the artifact.
- [ ] `render-qa-results.sh` wrote `qa/test-results/QA-results-{ID}.md` with `version: 2` frontmatter and the per-verdict structural rules satisfied.
- [ ] FR-1 final-message line is the **last** line of the response: `Verdict: <V> | Passed: <N> | Failed: <N> | Errored: <N>`.

## Relationship to Other Skills

| Task | Recommended Approach |
|------|---------------------|
| Document requirements first | Use `documenting-features`, `documenting-chores`, or `documenting-bugs` |
| Review requirements | Use `reviewing-requirements` |
| Build QA test plan | Use `documenting-qa` (prerequisite for this skill) |
| Create implementation plan | Use `creating-implementation-plans` |
| Implement the plan | Use `implementing-plan-phases` |
| Execute chore or bug fix | Use `executing-chores` or `executing-bug-fixes` |
| Reconcile after PR review | Use `reviewing-requirements` — code-review reconciliation mode (optional but recommended) |
| **Execute QA verification** | **Use this skill (`executing-qa`)** |
| Merge PR and reset to main | Use `finalizing-workflow` |

> Note: The `reviewing-requirements` test-plan reconciliation mode remains available as a standalone skill but is no longer invoked by the orchestrator between `documenting-qa` and `implementing-plan-phases` (per FR-11 Option B decision for FEAT-018).

## References

- [QA return contract](references/qa-return-contract.md) — artifact schema, final-message line, workflow-state findings JSON.
