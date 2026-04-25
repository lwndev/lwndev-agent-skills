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

Write and run adversarial tests against the change on the current branch. Grade the run on what the tests produce, not on what is said about them. With no supported test framework detected, fall through to a structured exploratory review covering the five adversarial dimensions.

## When to Use This Skill

- After `documenting-qa` produces a v2 plan at `qa/test-plans/QA-plan-{ID}.md`
- Invoked by the orchestrator at feature step `5+N+3` / chore-bug step 6 (post-FEAT-018 chain-table numbering)
- Manually via `/executing-qa {ID}` against a checked-out feature branch

## Arguments

- **When argument is provided**: Match against requirement IDs by prefix. The prefix sets the type: `FEAT-` (feature), `CHORE-` (chore), `BUG-` (bug). Load the corresponding test plan from `qa/test-plans/QA-plan-{ID}.md`.
- **When no argument is provided**: Ask the user for a requirement ID.

## Quick Start

1. Accept a requirement ID
2. Run capability discovery and compose the `qa` persona overlay
3. Load the v2 test plan
4. Mode-route: test-framework (write + run) OR exploratory-only (structured review)
5. Compute the reconciliation delta against the requirements doc
6. Emit the version-2 results artifact
7. Exit; the stop hook validates structural conformance

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

- **Error messages from `fail` calls** -- users need the reason the skill halted. Surface script and tool stderr verbatim (e.g., `capability-discovery.sh` / `persona-loader.sh` / `git diff` / `testCommand` failures) and the stop-hook block message when structural validation fails.
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts.
- **Interactive prompts** -- any prompt that blocks the workflow and requires user input (e.g., the requirement ID prompt when no argument is provided, the missing-test-plan error pointing to `documenting-qa`, the pointer prompt when there are no branch changes to test).
- **Findings display from `reviewing-requirements`** -- N/A for this skill (it does not consume reviewing-requirements findings); bullet retained for consistency with the canonical template.
- **FR-14 console echo lines** -- `[model] step {N} ({skill}) -> {tier} (...)` audit-trail lines emitted by `prepare-fork.sh`. The Unicode `->` is the documented emitter format; do not rewrite to ASCII. (Typically not emitted here since this skill runs in main context, not forked, but retained for cross-skill consistency.)
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim.
- **User-visible state transitions** -- pause, advance, and resume announcements (at most one line each).

### Fork-to-orchestrator return contract

`executing-qa` runs in **main context** (feature chain step 5+N+3; chore/bug chain step 6), **not** as an Agent fork. It returns its result directly to the user, not to a parent orchestrator. The `done | artifact=<path> | <note>` / `failed | <reason>` shapes do **not** apply to this skill -- there is no subagent boundary. Structural conformance of the emitted artifact (`qa/test-results/QA-results-{ID}.md`) is enforced by the Stop hook at `scripts/stop-hook.sh`, which validates frontmatter fields, the verdict enum, required sections, and per-verdict structural rules (`Failed: 0` for PASS, failing-test names for ISSUES-FOUND, stack trace for ERROR, `Reason:` line for EXPLORATORY-ONLY). The lite narration rules and load-bearing carve-outs above still govern the skill's output.

**Precedence**: when a load-bearing carve-out (error message, `[warn]` structured log, interactive prompt, etc.) conflicts with a lite-narration rule, the carve-out wins and MUST be emitted verbatim even if it reads like narration.

## State File Management

At skill start, create `.sdlc/qa/.executing-active` via Write (empty file). This signals the stop hook that `executing-qa` is active. The stop hook removes it on success; in orchestrated workflows the orchestrator cleans it up after return.

## Important: Bash-for-scripts-only

`Bash` is in `allowed-tools` so this skill can run `capability-discovery.sh`, `persona-loader.sh`, `git diff`, and the framework-specific `testCommand`. Do NOT use Bash for output formatting, status messages, progress echoes, or `echo` statements. All user communication goes through direct response text, not shell `echo`.

## Input

The user provides a requirement ID in one of these formats:

- `FEAT-XXX` — Feature requirement
- `CHORE-XXX` — Chore / maintenance task
- `BUG-XXX` — Bug report

If no ID is provided, ask for one.

## Step 1: Run capability discovery and compose the persona

1. **Resolve the consumer repo root** via `git rev-parse --show-toplevel`. This is the directory inspected for test framework and test command.

2. **Capability discovery**: if a fresh `/tmp/qa-capability-{ID}.json` already exists from this session (produced by `documenting-qa`) with mtime within the last hour, reuse it. Otherwise run:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/capability-discovery.sh <consumer-root> <ID>
   ```
   Capture the emitted JSON. Fields: `mode` (`test-framework` | `exploratory-only`), `framework`, `packageManager`, `testCommand`, `language`.

   If the plan's embedded capability report differs from the fresh one (e.g., framework changed since the plan was built), use the fresh one and note the drift in the artifact's `## Capability Report`.

   If `capability-discovery.sh` exits non-zero, treat as `mode: exploratory-only` with a recorded reason.

3. **Compose the `qa` persona overlay**:
   ```
   source ${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/persona-loader.sh
   load_persona qa ${CLAUDE_PLUGIN_ROOT}/skills/executing-qa
   ```
   If `load_persona` returns non-zero, abort with the error — do not silently substitute a default persona. The persona directives govern the tester mindset for the run.

## Step 2: Load the test plan

Read `qa/test-plans/QA-plan-{ID}.md`. If it does not exist, stop with an actionable error:

> No test plan found at `qa/test-plans/QA-plan-{ID}.md`. Run `documenting-qa` first.

Validate the plan is version-2 (frontmatter contains `version: 2`). If the `version` field is absent or is `1`, refuse with a specific error:

> Test plan is version 1 (pre-FEAT-018). Refusing to run the executable-oracle runner against a legacy closed-loop plan. Re-run `documenting-qa` to regenerate as version 2.

## Step 3: Mode selection

- If `capability.mode == "test-framework"`: proceed to Step 4 (write-and-run loop).
- If `capability.mode == "exploratory-only"`: proceed to Step 5 (exploratory review).

### Edge case 5: clean branch vs main → ERROR

Before writing any tests, run `git diff main...HEAD`. If the diff is empty (no changes on the branch), set verdict to `ERROR` with `Reason: no changes to test relative to main` and jump to Step 7 (reconciliation delta) and Step 8 (emit artifact). Do not write tests; do not run the framework.

## Step 4: Test-framework mode — write and run

For each P0/P1 scenario in the test plan whose `mode: test-framework` marker is set:

1. **Write a test file** in the framework's conventions, under its standard test root, with a `qa-` filename prefix tying the file to this run. Defaults by framework:
   - vitest / jest: `__tests__/qa-<dimension>.spec.ts` (or `.test.ts` per project config)
   - pytest: `tests/test_qa_<dimension>.py`
   - go test: `qa_<dimension>_test.go` next to the package under test

   Create the parent directory if absent (edge case 6). Each file implements the plan's scenarios for that dimension, following the suggested test shape in the scenario line.

2. **Execute the framework** via `capability.testCommand` (e.g., `npm test`, `npx vitest run`, `pytest`, `go test ./...`). Capture stdout, stderr, exit code, and wall-clock duration.

3. **Parse results**: total test count, passed count, failed count, errored count, failing test names, and truncated failing output (first 2000 chars per failing test or first 50 lines, whichever is shorter).

4. **Commit the written test files** to the feature branch as part of the run's output:
   ```
   git add <test-files>
   git commit -m "qa({ID}): add executable QA tests from executing-qa run"
   ```

### Verdict derivation (test-framework mode)

Derive the verdict from the framework's actual output — never from self-report:

- All written tests passed AND at least one scenario was exercised: `PASS`
- Any written test failed: `ISSUES-FOUND`
- Runner could not compile/parse the written tests (non-zero exit with no test output, framework crash, import error): `ERROR`
- No tests were written because every scenario was `exploratory`: fall through to Step 5

### Edge case 3: compile errors → ERROR, no retry

If the runner fails to compile or parse the written tests, verdict is `ERROR` and error traces are included in the artifact's `## Findings` or `## Execution Results` section. **Do not retry** — the stop hook accepts a valid `ERROR` artifact as a complete run.

### Edge case 6: missing test directory

If the conventional test directory for the detected framework does not exist, create it. Normal for first-time QA runs on a fresh repo.

## Step 5: Exploratory-only mode

Produce a structured exploratory review. For each of the five adversarial dimensions, surface either at least one finding OR an explicit non-applicability justification. An empty dimension fails stop-hook validation.

Dimensions:
- **Inputs** — malformed, empty, boundary, encoding, excessive size, injection
- **State transitions** — cancellation, interruption, idempotency, concurrent invocations
- **Environment** — offline, low disk, slow network, wrong locale/timezone
- **Dependency failure** — external API 5xx/4xx/timeout, rate limiting, partial response
- **Cross-cutting** — accessibility, internationalization, concurrency, permissions

Populate the artifact's `## Exploratory Mode` section with a `Reason:` line explaining the fallback (e.g., `"No supported test framework detected in consumer repo. Detection attempted: vitest, jest, pytest, go test."`). Set verdict to `EXPLORATORY-ONLY`.

## Step 5.5: Build-health gate (BUG-013)

After the test run (test-framework or exploratory-only) but before the reconciliation delta:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-build-health.sh" --no-interactive --skip-test
```

`--skip-test` avoids re-running the suite Step 4 already executed. See the script header for full semantics. If the gate exits non-zero:

- Force the QA verdict to `ISSUES-FOUND` (regardless of test-framework results).
- Add a finding to `## Findings` describing the failing build-health stage (e.g., `lint failed: 24 prettier violations`) with the failing command output excerpt — surfaced verbatim from the script's stderr.

## Step 6: Reconciliation Delta (FR-5)

After the run completes, read the requirements document. **This is the one and only time the requirements doc is consulted** — the planning skill (`documenting-qa`) is forbidden from reading it, so the delta here is the audit trail of spec-demanded vs. QA-tested.

Resolve the requirements-doc path from the ID with:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh" "<ID>"
```

The script maps the prefix (`FEAT-`, `CHORE-`, `BUG-`) to the correct directory (`requirements/features/`, `requirements/chores/`, `requirements/bugs/`) and globs `{ID}-*.md`. Exit codes: `0` on exactly-one match (path on stdout); `1` on zero matches — exit 1 triggers **edge case 7** (reconciliation delta skipped with reason, continue to Step 8); `2` on ambiguous (multiple files for the same ID signals workspace inconsistency — log a warning and pick the first alphabetically); `3` on malformed/missing ID.

Produce a **bidirectional** delta:

### Coverage surplus
Enumerate scenarios exercised (or reported-on in exploratory mode) that do not correspond to any FR / NFR / AC / edge case in the spec. Not automatically bad — may indicate diligent adversarial testing or over-testing.

### Coverage gap
Enumerate FRs / NFRs / ACs / edge cases in the spec with **no** corresponding scenario in the plan. A gap signals either an incomplete plan or an over-detailed spec.

### Summary counts
Emit `coverage-surplus: N` and `coverage-gap: N` lines in the `## Reconciliation Delta` → `### Summary` block so downstream tooling can tally the delta size.

### Edge case 7: missing requirements doc

If no requirements doc exists for the ID, **skip** the reconciliation delta. Emit `Reconciliation delta skipped: no requirements doc for {ID}` under `## Reconciliation Delta` → `### Summary` and continue to Step 8. Do not error out — a missing spec is a different failure mode than an incorrect one.

## Step 7: Emit the version-2 results artifact

Save the artifact to `qa/test-results/QA-results-{ID}.md` using the schema from [assets/test-results-template-v2.md](assets/test-results-template-v2.md). Create the `qa/test-results/` directory if absent.

Frontmatter (required):
- `id: {full ID}`
- `version: 2`
- `timestamp: <ISO-8601>`
- `verdict: PASS | ISSUES-FOUND | ERROR | EXPLORATORY-ONLY`
- `persona: qa`

Required top-level sections (in order):
- `## Summary`
- `## Capability Report`
- `## Execution Results` (required for PASS, ISSUES-FOUND, ERROR; optional for EXPLORATORY-ONLY)
- `## Scenarios Run`
- `## Findings`
- `## Reconciliation Delta`
- `## Exploratory Mode` (required for EXPLORATORY-ONLY only)

Per-verdict structural rules enforced by the stop hook:
- **PASS**: `Failed: 0` must appear in `## Execution Results`.
- **ISSUES-FOUND**: `## Findings` must list at least one failing test name (not a placeholder).
- **ERROR**: a stack trace must appear somewhere in the artifact.
- **EXPLORATORY-ONLY**: `## Exploratory Mode` must include a `Reason:` line.

## Step 8: Final message

State the verdict, the artifact path, and a 1-line run summary in the last message. The stop hook reads the artifact on disk — if it blocks, revise the artifact and try again. Do not summarize by repeating the artifact contents.

## Verification Checklist

Before finishing, verify:

- [ ] Capability discovery report produced (fresh or reused from `/tmp/qa-capability-{ID}.json`)
- [ ] Persona overlay composed via `persona-loader.sh`
- [ ] Mode routed to either test-framework or exploratory-only
- [ ] Test-framework mode: tests written and executed; verdict derived from actual runner output
- [ ] Exploratory-only mode: all five dimensions covered with findings or justifications; verdict `EXPLORATORY-ONLY`
- [ ] Reconciliation delta produced (or skipped with reason per edge case 7)
- [ ] v2 artifact written to `qa/test-results/QA-results-{ID}.md` with `version: 2` frontmatter
- [ ] Verdict is one of `PASS | ISSUES-FOUND | ERROR | EXPLORATORY-ONLY`
- [ ] Per-verdict structural rules satisfied (e.g. `Failed: 0` for PASS, failing-test names listed for ISSUES-FOUND, stack trace present for ERROR, `Reason:` line for EXPLORATORY-ONLY)

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
