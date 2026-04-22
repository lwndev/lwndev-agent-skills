---
name: documenting-qa
description: Builds an adversarial QA test plan for a feature, chore, or bug. Plans are built from the user-facing summary + PR/diff + capability report (NOT from the requirements doc) and organized by adversarial dimension (inputs, state transitions, environment, dependency failure, cross-cutting).
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
          command: "${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/scripts/stop-hook.sh"
argument-hint: <requirement-id>
---

# Documenting QA

Build an adversarial QA test plan from the user-facing summary of a change and the code that implements it — **not** from the requirements document that drove the implementation. You operate as a skeptical tester probing failure modes the engineers likely did not anticipate.

## When to Use This Skill

- User says "document qa", "create test plan", or "qa plan"
- User provides a requirement ID (`FEAT-XXX`, `CHORE-XXX`, `BUG-XXX`) for QA planning
- After implementation has landed on a branch (and ideally after a PR is open) — so you have real code diff and a user-facing PR summary to plan against

## Arguments

- **When argument is provided**: Match the argument against requirement IDs by prefix. The ID prefix determines the type: `FEAT-` (feature), `CHORE-` (chore), `BUG-` (bug). Optionally a `--pr <number>` flag may be provided to target a specific PR explicitly.
- **When no argument is provided**: Ask the user for a requirement ID.

## Quick Start

1. Accept a requirement ID (and optional `--pr <number>`)
2. Run capability discovery
3. Load the `qa` persona overlay
4. Gather the user-facing summary — from the PR (preferred) or the requirements doc's `## User Story` section only
5. Gather code context — PR diff or `git diff main...HEAD`
6. Build adversarial scenarios organized by dimension
7. Emit a version-2 plan artifact to `qa/test-plans/QA-plan-{ID}.md`
8. Exit; the stop hook validates structural conformance

## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration. This skill runs in the orchestrator's main conversation (feature chain step 5; chore/bug chain step 3), so its output flows directly to the user.

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

- **Error messages from `fail` calls** -- users need the reason the skill halted. Surface script and tool stderr verbatim (e.g., `capability-discovery.sh` / `persona-loader.sh` / `gh pr view` / `git diff` failures) and the stop-hook block message when structural validation fails.
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts.
- **Interactive prompts** -- any prompt that blocks the workflow and requires user input (e.g., the requirement ID prompt when no argument is provided, the user-summary prompt when no PR exists and no `## User Story` section is found, the "what to test" pointer prompt when there are no branch changes).
- **Findings display from `reviewing-requirements`** -- N/A for this skill (it does not consume reviewing-requirements findings); bullet retained for consistency with the canonical template.
- **FR-14 console echo lines** -- `[model] step {N} ({skill}) -> {tier} (...)` audit-trail lines emitted by `prepare-fork.sh`. The Unicode `->` is the documented emitter format; do not rewrite to ASCII. (Typically not emitted here since this skill runs in main context, not forked, but retained for cross-skill consistency.)
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim.
- **User-visible state transitions** -- pause, advance, and resume announcements (at most one line each).

### Fork-to-orchestrator return contract

`documenting-qa` runs in **main context** (feature chain step 5; chore/bug chain step 3), **not** as an Agent fork. It returns its result directly to the user, not to a parent orchestrator. The `done | artifact=<path> | <note>` / `failed | <reason>` shapes do **not** apply to this skill -- there is no subagent boundary. Structural conformance of the emitted artifact (`qa/test-plans/QA-plan-{ID}.md`) is enforced by the Stop hook at `scripts/stop-hook.sh`, which validates frontmatter fields, required sections, scenario shape, and the no-`FR-N`-in-`Scenarios` guard. The lite narration rules and load-bearing carve-outs above still govern the skill's output.

**Precedence**: when a load-bearing carve-out (error message, `[warn]` structured log, interactive prompt, etc.) conflicts with a lite-narration rule, the carve-out wins and MUST be emitted verbatim even if it reads like narration.

## State File Management

At the start of this skill, create `.sdlc/qa/.documenting-active` via the Write tool (empty content). This signals the stop hook that `documenting-qa` is the active skill. The stop hook removes the state file on success. In orchestrated workflows the orchestrator cleans it up after this skill returns.

## Important: Bash-for-scripts-only

This skill includes `Bash` in allowed-tools so it can invoke `capability-discovery.sh`, `persona-loader.sh`, `gh pr view`, and `git diff`. Do NOT use Bash for output formatting, status messages, progress echoes, or any communication with the user. All communication with the user happens through direct response text, not through shell `echo`.

## Step 1: Resolve the requirement ID and run capability discovery

1. **Parse the ID prefix** → type (feature / chore / bug). Establish the expected requirements-doc path (`requirements/features/{ID}-*.md`, `requirements/chores/{ID}-*.md`, or `requirements/bugs/{ID}-*.md`) — you will read **only** its `## User Story` section if no PR exists (see Step 2).
2. **Resolve the consumer repo root** via `git rev-parse --show-toplevel`. This is the directory you will inspect for test-framework detection.
3. **Run capability discovery**:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/scripts/capability-discovery.sh <consumer-root> <ID>
   ```
   Capture the emitted JSON (also written to `/tmp/qa-capability-<ID>.json`). The report has fields: `mode` (`test-framework` | `exploratory-only`), `framework`, `packageManager`, `testCommand`, `language`.
4. If `capability-discovery.sh` exits non-zero, note the error and proceed as `mode: exploratory-only`. The capability report informs the plan's `## Capability Report` section and constrains which scenarios are feasible under test-framework mode.

## Step 2: Gather the user-facing summary (NOT the full requirements doc)

You need a 2–5 sentence user-facing summary of what the change does. The source depends on whether a PR is open:

**Precedence:**
1. **PR-first**: If a PR exists for this feature branch, run `gh pr view --json title,body` (or `gh pr view <number> --json title,body` when `--pr` was provided). Set `user_summary = PR title + first paragraph of PR body`.
2. **User Story fallback**: If no PR is open, read **only** the `## User Story` section of the requirements doc — use Grep/Read to extract that single heading's content.
3. **Ask the user**: If no PR exists and no `## User Story` section is found, ask the user to describe the change in 2–5 sentences.

**Forbidden reads during planning.** Do NOT read `requirements/features/FEAT-*.md`, `requirements/chores/CHORE-*.md`, or `requirements/bugs/BUG-*.md` beyond the isolated `## User Story` block. Specifically, do NOT read the FR grid, NFRs, acceptance criteria, edge cases, or implementation plans. The stop hook verifies no `FR-N` references leak into the `## Scenarios (by dimension)` section; if you find yourself writing `FR-3 covers X`, you are doing it wrong.

The point of this prohibition: QA must probe failure modes the spec did not anticipate. Reading the spec biases the plan toward confirming what engineers already planned for.

## Step 3: Gather code context

- **With PR**: `gh pr diff <number>` (omit `<number>` for the branch's default PR).
- **No PR but on a feature branch**: `git diff main...HEAD`.
- **No branch changes**: ask the user for a pointer to what to test.

The diff + the user summary + the capability report are the only inputs you plan against.

## Step 4: Compose the `qa` persona overlay

```
source ${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/scripts/persona-loader.sh
load_persona qa ${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa
```

If `load_persona` returns non-zero (missing or malformed persona file), abort with the error — do not silently substitute a default persona. The emitted persona content becomes part of the planning context; its directives are what you follow when generating scenarios.

> The `--persona <name>` CLI flag is a future feature; for now the persona is always `qa`.

## Step 5: Build the adversarial plan

For each of the five adversarial dimensions, generate P0/P1/P2-prioritized scenarios. Each scenario line in the artifact MUST match the shape:

```
- [P0|P1|P2] <description> | mode: test-framework|exploratory | expected: <test shape>
```

Dimensions:
- **Inputs** — malformed, empty, boundary, encoding, excessive size, injection
- **State transitions** — cancellation, interruption, idempotency, concurrent invocations
- **Environment** — offline, low disk, slow network, wrong locale/timezone
- **Dependency failure** — external API 5xx/4xx/timeout, rate limiting, partial response
- **Cross-cutting** — accessibility, internationalization, concurrency, permissions

For any dimension that truly does not apply, write a justification in `## Non-applicable dimensions` (e.g., `- a11y: this feature has no UI surface`). Blanket "not applicable" with no justification is rejected by the stop hook.

**Execution mode per scenario**:
- `test-framework` — feasible to express as an automated test under the detected framework (Step 1's capability report). Use only when `capability.mode == "test-framework"`.
- `exploratory` — requires human judgment, manual reproduction, or environmental setup outside the automated framework.

Prioritize ruthlessly: P0 = user-visible regression risk or data loss, P1 = degraded UX, P2 = polish / edge case.

## Step 6: Emit the version-2 plan artifact

Write the plan to `qa/test-plans/QA-plan-{ID}.md` using the schema from [assets/test-plan-template-v2.md](assets/test-plan-template-v2.md).

Frontmatter (required fields):
- `id: {full ID, e.g. FEAT-018}`
- `version: 2`
- `timestamp: <ISO-8601>`
- `persona: qa`

Sections (required, in order):
- `## User Summary`
- `## Capability Report`
- `## Scenarios (by dimension)` — with all five dimension subheadings, each containing either scenario lines or a matching justification in the next section
- `## Non-applicable dimensions`

Create the `qa/test-plans/` directory if it does not exist.

## Step 7: Verify and exit

State in your last message that the plan file path is `qa/test-plans/QA-plan-{ID}.md`. The stop hook validates structural conformance (frontmatter fields, required sections, scenario shape with priorities and modes, and the no-`FR-N`-in-`Scenarios` guard). If the hook blocks, fix the flagged issue and try again.

## Verification Checklist

Before finishing, verify:

- [ ] Capability discovery report produced (check `/tmp/qa-capability-{ID}.json` exists)
- [ ] Persona overlay composed via `persona-loader.sh`
- [ ] User summary gathered from PR title+body OR `## User Story` only — the full requirements doc was NOT read
- [ ] Plan artifact saved to `qa/test-plans/QA-plan-{ID}.md` with `version: 2` frontmatter
- [ ] Scenarios organized by dimension (not by FR row, not by AC)
- [ ] Every scenario has a priority tag `[P0|P1|P2]` and a `mode:` tag
- [ ] Non-applicable dimensions have justifications (no blanket dismissal)
- [ ] The `## Scenarios (by dimension)` section contains no `FR-N` references

## Relationship to Other Skills

| Task | Recommended Approach |
|------|---------------------|
| Document requirements first | Use `documenting-features`, `documenting-chores`, or `documenting-bugs` |
| Review requirements | Use `reviewing-requirements` |
| **Build QA test plan** | **Use this skill (`documenting-qa`)** |
| Create implementation plan | Use `creating-implementation-plans` |
| Implement the plan | Use `implementing-plan-phases` |
| Execute chore or bug fix | Use `executing-chores` or `executing-bug-fixes` |
| Reconcile after PR review | Use `reviewing-requirements` — code-review reconciliation mode (optional but recommended) |
| Execute QA verification | Use `executing-qa` (requires the v2 test plan from this skill) |
| Merge PR and reset to main | Use `finalizing-workflow` |

> Note: The `reviewing-requirements` test-plan reconciliation mode remains available as a standalone skill but is no longer invoked by the orchestrator between `documenting-qa` and `implementing-plan-phases` (per FR-11 Option B decision for FEAT-018).
