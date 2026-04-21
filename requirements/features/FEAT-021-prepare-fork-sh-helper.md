# Feature Requirements: `prepare-fork.sh` — pre-fork ceremony helper script

## Overview

Add a new plugin-shared script `prepare-fork.sh` that collapses the four-step pre-fork ceremony currently documented as prose in `orchestrating-workflows/SKILL.md` ("Forked Steps") into a single composite invocation. The script reads the sub-skill's `SKILL.md`, resolves the FEAT-014 model tier, writes the `modelSelections` audit-trail entry, and emits the FR-14 console echo line — all via existing `workflow-state.sh` subcommands — then prints the resolved tier on stdout so the orchestrator can pass it verbatim as the Agent tool's `model` parameter.

## Feature ID

`FEAT-021`

## GitHub Issue

[#181](https://github.com/lwndev/lwndev-marketplace/issues/181)

## Priority

High — #181 is flagged as "the single biggest script win in the catalogue" with an estimated savings of ~400–600 tokens per invocation × ~10 fork sites per feature workflow = **4,000–6,000 tokens per feature workflow**. It is an additive script — no caller has to change in the same PR beyond the orchestrator itself, and it composes over already-scripted `workflow-state.sh` subcommands so it carries no new classifier, state-file, or audit-trail logic. Part of the #179 prose-to-script backlog (item 9.2); standalone from items 9.1 and 9.3–9.8 per the issue body.

## User Story

As the orchestrator executing a forked SDLC step, I want a single `prepare-fork.sh <ID> <stepIndex> <skill-name> [--mode M] [--phase P]` call to perform the entire pre-fork ceremony (SKILL.md read, tier resolution, audit-trail write, FR-14 echo) so that the main-context prompt no longer has to re-interpret ~400–600 tokens of procedural prose at every fork site and the four steps stay in lockstep (they share inputs; any drift between them is a bug).

## Motivation

The current "Forked Steps" section of `orchestrating-workflows/SKILL.md` (steps 1–4 of the fork recipe, lines ~295–345 at the time of writing) describes a four-step ceremony that every forked step must execute **before** spawning the Agent tool:

1. Read the sub-skill's `SKILL.md` content from `${CLAUDE_SKILL_DIR}/skills/{skill-name}/SKILL.md`.
2. Resolve the tier via `workflow-state.sh resolve-tier` (forwarding any CLI `--model` / `--complexity` / `--model-for` flags).
3. Write the `modelSelections` audit-trail entry via `workflow-state.sh record-model-selection` **before** the fork executes (NFR-3 guarantees a crashed fork still leaves a trace).
4. Emit the FR-14 console echo line — baseline-locked variants use the literal `baseline-locked` tag; non-locked variants use `wi-complexity=<tier>`; hard-override-below-baseline downgrades emit the documented Edge Case 11 warning line.

This ceremony is invoked at ~10 fork sites per feature workflow (1 standard-mode `reviewing-requirements` fork at step 2, plus up to 2 reconciliation-mode `reviewing-requirements` forks — one after QA planning, one after PR review — 1 `creating-implementation-plans` fork, N `implementing-plan-phases` forks, 1 `pr-creation` fork, 1 `finalizing-workflow` fork) and 4–6 fork sites per chore or bug workflow. `documenting-qa` and `executing-qa` themselves run in main context (see the chain step tables in `orchestrating-workflows/SKILL.md`); the reconciliation forks that surround them are additional `reviewing-requirements` invocations, not QA forks. Every invocation re-reads the same four-step procedural prose.

The four steps also share a single canonical input set — `{ID}`, `{stepIndex}`, `{skill-name}`, optional `{mode}`, optional `{phase}`, and the three CLI flags forwarded from workflow-level argv. Keeping the orchestration of those four calls as prose in SKILL.md means:

- Any edit to the ceremony (e.g. the FR-14 echo format in FEAT-014) requires the orchestrator's model to correctly re-apply the change at every call site on first read — no structural enforcement exists.
- The model must repeatedly compute `complexityStage` from the state file, derive the `--mode` / `--phase` arguments for `record-model-selection`, and remember the baseline-lock vs non-locked echo format — all recomputation the model already did at a previous fork site in the same workflow.
- The token cost of the prose is duplicated at every fork site: ~400–600 tokens depending on whether the variant includes Edge Case 11's baseline-bypass warning.

Scripting the ceremony removes all three costs at once. The orchestrator's prose shrinks to a single command (`tier=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/prepare-fork.sh {ID} {stepIndex} {skill-name} [--mode M] [--phase P] [--cli-model ...] [--cli-complexity ...] [--cli-model-for ...])`) and the four sub-steps become internal function calls inside the script. The Agent-tool fork itself stays in main context (it cannot be scripted — the Agent tool is an LLM primitive, not a CLI), but every preparatory step that *can* be scripted now is.

## Current State

`orchestrating-workflows/SKILL.md` contains the four-step ceremony as numbered prose (the "Forked Steps" section). Two subcommands of `workflow-state.sh` are already in place and are wired to the FEAT-014 requirements doc:

- `workflow-state.sh resolve-tier <ID> <step-name> [--cli-model <tier>] [--cli-complexity <tier>] [--cli-model-for <step:tier>]` — Implemented at `workflow-state.sh` `resolve-tier)` dispatch (~line 1657). Reads the step baseline from `_step_baseline`, reads `_step_baseline_locked` for the lock predicate, reads persisted `complexity` and `modelOverride` from the state file, walks the override chain (CLI per-step hard → CLI blanket hard → CLI complexity → state-file override → computed tier), and prints the resolved tier (`haiku`, `sonnet`, or `opus`) on stdout. Exit codes: `0` on success; `1` on unknown flag or missing state file.
- `workflow-state.sh record-model-selection <ID> <stepIndex> <skill> <mode> <phase> <tier> <complexityStage> <startedAt>` — Implemented at `workflow-state.sh` `record-model-selection)` dispatch (~line 1645). Appends a `modelSelections` entry to the state file. All seven argument slots after `<ID>` are required; pass the literal string `null` for `<mode>` / `<phase>` when unused.

Neither subcommand reads the sub-skill's `SKILL.md`, nor do either emit the FR-14 console echo line — those two pieces of the ceremony remain prose-only. The orchestrator currently performs them inline in its main context.

The `workflow-state.sh` script has no plugin-shared peer scripts that it depends on from `plugins/lwndev-sdlc/scripts/` — it stands alone. FEAT-020 has already landed the `plugins/lwndev-sdlc/scripts/` directory with ten cross-cutting scripts plus a `tests/` subdirectory and a `README.md` script table. `prepare-fork.sh` installs into that existing directory as an eleventh sibling; its runtime path is `${CLAUDE_PLUGIN_ROOT}/scripts/prepare-fork.sh`.

## Script Specification

One new script lands: `plugins/lwndev-sdlc/scripts/prepare-fork.sh`. It is self-contained — no new library dependencies, no new state-file fields. Its only callees are `workflow-state.sh` subcommands already shipped by FEAT-014.

### FR-1: Command-line interface

**Syntax:**

```
prepare-fork.sh <ID> <stepIndex> <skill-name> [--mode <mode>] [--phase <phase>]
                [--cli-model <tier>] [--cli-complexity <tier>] [--cli-model-for <step:tier>]...
```

**Positional arguments (all three required):**

- `<ID>` — Work-item ID (`FEAT-NNN`, `CHORE-NNN`, `BUG-NNN`). Must correspond to an existing `.sdlc/workflows/{ID}.json` state file. If the state file does not exist, the script exits `2` with the message `Error: workflow state file .sdlc/workflows/{ID}.json not found` on stderr.
- `<stepIndex>` — Zero-based index of the step in the chain's `steps` array (integer). Must be numeric; non-numeric values exit `2` with `Error: <stepIndex> must be a non-negative integer; got '<value>'` on stderr.
- `<skill-name>` — Canonical fork step-name (see "Fork Step-Name Map" in `orchestrating-workflows/SKILL.md`). Must be one of `reviewing-requirements`, `creating-implementation-plans`, `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `finalizing-workflow`, `pr-creation`. Any other value exits `2` with `Error: unknown skill-name '<value>'. Must be one of: <list>` on stderr.
  - **PR-creation caveat**: the workflow-state step array records the PR-creation step with `"skill": "orchestrator"` (see `workflow-state.sh` ~line 846) because the orchestrator itself creates the PR inline. The FEAT-014 baseline map keys off `pr-creation` for that same step. **The caller is responsible for passing `pr-creation` — not `orchestrator` — to `prepare-fork.sh` at the PR-creation fork site.** The orchestrator prose updated per FR-4 makes this explicit; no translation logic is added to the script itself.

**Optional flags (may appear before or after positional args):**

- `--mode <mode>` — Mode argument for `record-model-selection`. Valid only when `<skill-name>` is `reviewing-requirements` (where `<mode>` is `standard`, `test-plan`, or `code-review`). When `<skill-name>` is anything else and `--mode` is provided, the script exits `2` with `Error: --mode is only valid for reviewing-requirements; got skill '<skill-name>'` on stderr. When absent, the `<mode>` slot of `record-model-selection` receives the literal string `null`.
- `--phase <phase>` — Phase number for `record-model-selection`. Valid only when `<skill-name>` is `implementing-plan-phases`. When `<skill-name>` is anything else and `--phase` is provided, the script exits `2` with `Error: --phase is only valid for implementing-plan-phases; got skill '<skill-name>'` on stderr. When absent, the `<phase>` slot receives the literal string `null`. The value is passed through verbatim (not validated as numeric) because `record-model-selection` accepts the string form.
- `--cli-model <tier>` — Forwarded to `resolve-tier --cli-model`. Values: `haiku`, `sonnet`, `opus`. Validation is delegated to `resolve-tier`.
- `--cli-complexity <tier>` — Forwarded to `resolve-tier --cli-complexity`. Validation is delegated to `resolve-tier`.
- `--cli-model-for <step:tier>` — Forwarded to `resolve-tier --cli-model-for`. May be repeated (multiple `--cli-model-for step1:tier1 --cli-model-for step2:tier2` is allowed). The script accumulates all occurrences and forwards each through to `resolve-tier`.

**Unknown flags:** exit `2` with `Error: unknown flag '<flag>'. See prepare-fork.sh --help` on stderr.

**`--help`**: when `--help` or `-h` appears **anywhere** in argv, the script prints its usage to stdout and exits `0` before any other parsing or validation happens. Help takes precedence over positional-arg validation (an incomplete but help-requesting invocation still gets help, not an arg-validation error). The usage message must include the syntax line, a one-line description of each positional arg and flag, and an example invocation.

### FR-2: Behavior

On successful invocation, the script performs the four-step ceremony in sequence:

**Step 1 — Read SKILL.md**

Resolve `${CLAUDE_PLUGIN_ROOT}` at runtime:

1. If the environment variable `CLAUDE_PLUGIN_ROOT` is set and non-empty, use it verbatim.
2. Otherwise, derive it from the script's own path: `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)` — because the script lives at `${CLAUDE_PLUGIN_ROOT}/scripts/prepare-fork.sh`, its parent-of-parent is the plugin root.

Construct the SKILL.md path as `${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/SKILL.md`. Verify the file exists **and** is readable via `[[ -r "$skill_md_path" ]]`; if the test fails for any reason (file missing, permission denied, directory traversal blocked), exit `3` with `Error: SKILL.md for '{skill-name}' cannot be read at <resolved-path>` on stderr. A single exit code collapses "not found" and "present but unreadable" — both are equally terminal from the script's perspective, and the orchestrator's retry logic does not benefit from distinguishing them. **Do not print the SKILL.md contents on stdout** — the script's stdout contract is reserved for the resolved tier (see FR-3). The file's readability is the contract that the orchestrator's subsequent Agent-tool fork prompt will be able to load it; the script does not need to relay its contents. (Rationale: `Read` is an LLM-primitive tool; the orchestrator will do its own Read in the same turn it calls this script. The script's job is to verify the file is readable so a broken SKILL.md path is caught before the fork spawns.)

**Step 2 — Resolve the tier**

Invoke `workflow-state.sh resolve-tier`, forwarding the three CLI flags when present:

```bash
tier=$("${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" resolve-tier "$ID" "$skill" \
  ${cli_model:+--cli-model "$cli_model"} \
  ${cli_complexity:+--cli-complexity "$cli_complexity"} \
  "${cli_model_for_args[@]}")
```

Where `${CLAUDE_SKILL_DIR}` is `${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows` — `workflow-state.sh` lives under the orchestrating-workflows skill, not the plugin-shared scripts directory (see `references/model-selection.md` lines 83–85: "the `resolve-tier` subcommand" of `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh`).

The script reads `$CLAUDE_SKILL_DIR` at runtime with the same fallback logic as `$CLAUDE_PLUGIN_ROOT`: environment variable if set, otherwise derive from the script location (`${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows`).

On non-zero exit from `resolve-tier`, propagate the exit code and the stderr message verbatim and abort the ceremony — no audit-trail entry is written, no echo line is emitted.

**Step 3 — Record the audit-trail entry**

Read `complexityStage` from the state file via `jq -r '.complexityStage // "init"' ".sdlc/workflows/${ID}.json"`. If `jq` is missing or the file is unreadable, exit `4` with `Error: cannot read complexityStage from state file — is jq installed?` on stderr.

Compute `startedAt` as `$(date -u +%Y-%m-%dT%H:%M:%SZ)`.

Invoke `workflow-state.sh record-model-selection`:

```bash
"${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" record-model-selection \
  "$ID" "$stepIndex" "$skill" "$mode" "$phase" "$tier" "$stage" "$startedAt"
```

`$mode` and `$phase` carry the literal string `null` when the corresponding flag is absent (see FR-1). On non-zero exit from `record-model-selection`, propagate the exit code and stderr message.

**Step 4 — Emit the FR-14 console echo line**

Read the baseline and lock predicate for the step:

```bash
baseline=$("${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" step-baseline "$skill")
locked=$("${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" step-baseline-locked "$skill")
```

(These two subcommands are not currently exposed by `workflow-state.sh`. See FR-3 for the contract update.)

Read the persisted complexity from the state file via `jq -r '.complexity // "medium"' ".sdlc/workflows/${ID}.json"`. Label this `wi_complexity`. **This value reflects the persisted work-item complexity, not any CLI override applied to `resolve-tier`.** The distinction is intentional: `--cli-complexity` adjusts the tier computation (Axis 2) for this invocation but does not mutate state-file `complexity`. The echo line's `wi-complexity=` token reports the state-file value so operators reading the echo trail see the stable signal baseline; CLI adjustments surface via the `override=` token instead.

Read the persisted `modelOverride` from the state file via `jq -r '.modelOverride // empty' ".sdlc/workflows/${ID}.json"`. Label this `state_override`. If the value is non-empty, it participates in the `override=` field; if empty, the field value is `none` when no CLI override applied either (see below).

Determine the effective override token for the echo line (precedence: per-step CLI flag > blanket CLI flag > CLI complexity > state override > `none`). The first non-empty wins:

- If a matching `--cli-model-for <skill>:<tier>` was passed, token is `cli-model-for:<tier>`.
- Else if `--cli-model <tier>` was passed, token is `cli-model:<tier>`.
- Else if `--cli-complexity <tier>` was passed, token is `cli-complexity:<tier>`.
- Else if `state_override` is non-empty, token is `state-override:<state_override>`.
- Else `none`.

Determine the phase-or-mode slot for the human-readable echo line:

- If `--mode` is present, slot is `mode=<mode>` (e.g., `mode=standard`).
- Else if `--phase` is present, slot is `phase=<phase>` (e.g., `phase=3`).
- Else omitted (no `(mode=...)` / `(phase=...)` parenthetical in the echo line).

Emit the echo line to stderr in one of three formats:

1. **Baseline-locked** (`locked == "true"`):
   ```
   [model] step <stepIndex> (<skill>) → <tier> (baseline=<baseline>, baseline-locked)
   ```
   The `wi-complexity=` and `override=` tokens are **not** emitted for baseline-locked steps (matching the documented format in SKILL.md's "Forked Steps" section example: `[model] step 11 (finalizing-workflow) → haiku (baseline=haiku, baseline-locked)`).

2. **Non-locked** (`locked == "false"`):
   ```
   [model] step <stepIndex> (<skill>[, <mode-or-phase-slot>]) → <tier> (baseline=<baseline>, wi-complexity=<wi_complexity>, override=<override-token>)
   ```

3. **Hard-override-below-baseline downgrade** (`tier` tier-ordinal is strictly less than `baseline` tier-ordinal, where ordering is `haiku=0 < sonnet=1 < opus=2`): emit the non-locked line **plus** an additional warning line after it:
   ```
   [model] Hard override --model <tier> bypassed baseline <baseline> for <skill>. Proceeding at user request.
   ```
   (Matches the documented Edge Case 11 format in SKILL.md's "Forked Steps" section.)

All echo output goes to stderr (not stdout), so the orchestrator's `tier=$(bash prepare-fork.sh ...)` capture gets only the tier on stdout. The script writes the echo line via `echo ... >&2`.

**Step 5 — Print the resolved tier on stdout**

After the audit-trail entry is written and the echo line is emitted, print the resolved tier as the only content on stdout, terminated by a newline:

```
haiku
```

(Or `sonnet` / `opus`, whichever was resolved.) Exit `0`.

### FR-3: `workflow-state.sh` contract addition

FR-2 Step 4 requires reading the step baseline and lock predicate from outside `workflow-state.sh`. Today, both are internal functions (`_step_baseline` and `_step_baseline_locked` at lines 163 and 179 respectively) and are not exposed as subcommands. This feature adds two trivial subcommands to `workflow-state.sh`:

**`workflow-state.sh step-baseline <step-name>`** — Print the baseline tier (`haiku`, `sonnet`, or `opus`) for the named step on stdout. Exit `0` on valid step-name; exit `2` with `Error: unknown step-name '<value>'` on stderr for unknown names. Thin wrapper around `_step_baseline`.

**`workflow-state.sh step-baseline-locked <step-name>`** — Print the literal string `true` or `false` on stdout. Exit `0` on valid step-name; exit `2` on unknown. Thin wrapper around `_step_baseline_locked`.

Both subcommands take exactly one argument. Both are additive (new dispatch branches in the case statement; no existing subcommand changes).

### FR-4: Orchestrator prose replacement

The "Forked Steps" section of `orchestrating-workflows/SKILL.md` is rewritten. Steps 1–4 of the current seven-step procedure collapse into a single bullet:

**Before** (four separate numbered steps totaling ~400–600 tokens):

> 1. Read the sub-skill's SKILL.md content: `${CLAUDE_SKILL_DIR}/skills/{skill-name}/SKILL.md`
> 2. **Resolve the tier (FEAT-014 FR-3)**. Call `resolve-tier` with the canonical step-name ...
> 3. **Write the audit trail entry (FEAT-014 FR-7, NFR-3)**. The write happens BEFORE the fork ...
> 4. **Emit the FR-14 console echo line** in the documented format ...

**After** (single bullet):

> 1. **Run the pre-fork ceremony**:
>    ```bash
>    tier=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/prepare-fork.sh" {ID} {stepIndex} {skill-name} \
>      ${mode:+--mode $mode} ${phase:+--phase $phase} \
>      ${cli_model:+--cli-model $cli_model} \
>      ${cli_complexity:+--cli-complexity $cli_complexity} \
>      ${cli_model_for:+--cli-model-for $cli_model_for})
>    ```
>    The script reads the sub-skill's `SKILL.md` (verifying it exists), resolves the FEAT-014 tier, writes the `modelSelections` audit-trail entry (NFR-3: before the fork executes), and emits the FR-14 console echo line to stderr. It prints the resolved tier on stdout. On non-zero exit, propagate the error and abort the fork; do **not** spawn the Agent tool.

Step 5 (spawn the Agent tool) and onwards remain as prose — they are LLM-primitive operations not representable as CLI calls.

The NFR-6 Agent-tool-rejection fallback (current step 7), the FR-11 retry-with-tier-upgrade (current step 8), and the artifact validation / state-advance (steps 9–10) are untouched.

### FR-5: Downstream documentation changes

Four references must be updated to mention the new script:

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — the "Forked Steps" section per FR-4.
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` — add a one-paragraph note after the FR-3 pseudocode section noting that live invocation goes through `prepare-fork.sh`, and that the pseudocode remains the canonical reference for the tier-resolution algorithm itself.
- `plugins/lwndev-sdlc/scripts/README.md` — add a new row to the "Script Table" for `prepare-fork.sh` with `FR` linking to this feature (e.g. `FEAT-021`) and a one-line purpose: "Run the FEAT-014 pre-fork ceremony (SKILL.md readability check, tier resolution, audit-trail write, echo line) and print the resolved tier." The table already exists; this is a single-row addition.
- `requirements/features/FEAT-014-adaptive-model-selection.md` — add a post-FEAT-014 note under the "Implementation" section linking to FEAT-021 for the current scripted entry point. FEAT-014's prose remains the canonical behavioral spec; FEAT-021 is its scripted composer.

### FR-6: Existing `workflow-state.sh` subcommand touch

No existing `workflow-state.sh` subcommand changes behavior. The two new subcommands (`step-baseline`, `step-baseline-locked`) per FR-3 are the only additions. No state-file schema changes. No new state-file fields.

## Output Format

The script writes the resolved tier as a single line on stdout (used by the orchestrator as `tier=$(bash prepare-fork.sh ...)`):

```
sonnet
```

The FR-14 echo line goes to stderr. Example for a non-locked step:

```
[model] step 2 (reviewing-requirements, mode=standard) → sonnet (baseline=sonnet, wi-complexity=medium, override=none)
```

Example for a baseline-locked step:

```
[model] step 11 (finalizing-workflow) → haiku (baseline=haiku, baseline-locked)
```

Example for an Edge Case 11 downgrade (stderr, two lines):

```
[model] step 4 (creating-implementation-plans) → haiku (baseline=sonnet, wi-complexity=low, override=cli-model:haiku)
[model] Hard override --model haiku bypassed baseline sonnet for creating-implementation-plans. Proceeding at user request.
```

## Non-Functional Requirements

### NFR-1: Error propagation

The script must never mask an error from `resolve-tier` or `record-model-selection`. On non-zero exit from either, the script:

1. Prints the child's stderr unchanged on its own stderr.
2. Exits with the child's exit code.
3. Does **not** emit the FR-14 echo line (because the tier may not have been resolved or the audit trail may be partial).
4. Does **not** print anything on stdout (orchestrator's `tier=$(...)` capture will be empty, which the orchestrator treats as "pre-fork ceremony failed — abort the fork").

**Ordering invariant**: If any of steps 2, 3, or 4 fail, all **earlier** steps' side effects remain (e.g., if step 4 fails, the `modelSelections` entry from step 3 is still in the state file). The orchestrator's retry logic handles this via the existing FR-11 retry-with-tier-upgrade path — the next attempt will simply append a new `modelSelections` entry, so the audit trail shows both attempts.

### NFR-2: Idempotency stance

The script is **not** idempotent — each call writes a new `modelSelections` entry. This is intentional and matches the FR-11 retry semantics: a retry-with-tier-upgrade is supposed to leave both the original and the retry entries in the audit trail. Callers must not invoke `prepare-fork.sh` for the same `<stepIndex>` twice without intending to record a retry.

### NFR-3: Performance

The script's wall-clock runtime must be dominated by the two `workflow-state.sh` subcommand invocations (each already O(ms) in practice). The script adds:

- One `jq` invocation to read `complexityStage`.
- One `jq` invocation to read `complexity`.
- One `jq` invocation to read `modelOverride`.
- Two additional `workflow-state.sh` invocations (`step-baseline`, `step-baseline-locked`).
- One `date -u` invocation.

Target: complete in under 300 ms on a modern development laptop. Acceptance check is "qualitative": if observed invocation time drifts above ~500 ms on representative hardware in manual testing, open a follow-up issue.

### NFR-4: Portability

Must work on Bash 3.2 (macOS system Bash) and Bash 4+. No Bash 4-only features (associative arrays, `&>>`, `mapfile` — none required anyway). Must work on Linux and macOS. Dependencies: `bash`, `jq`, `date`. `jq` is already a runtime dependency of `workflow-state.sh` and is verified at workflow init, so its availability is implicit.

### NFR-5: Testability

Exit codes are the primary contract. Every error path has a dedicated exit code:

- `0` — Success.
- `1+` — Propagated failure from `resolve-tier`, `record-model-selection`, `step-baseline`, or `step-baseline-locked`. The script forwards the child's exit code verbatim (typically `1` from these subcommands, but any non-zero child exit is passed through unchanged).
- `2` — Argument validation failure (missing positional, unknown flag, invalid `--mode` / `--phase` combination, non-numeric `stepIndex`, unknown `skill-name`).
- `3` — SKILL.md file cannot be read at resolved path (missing or permission-denied; collapsed per FR-2 Step 1).
- `4` — State file unreadable or `jq` missing.

Test fixtures must exercise every exit code, plus the three FR-14 echo line variants (baseline-locked, non-locked, Edge Case 11 downgrade).

### NFR-6: Compatibility with existing workflows in-flight

A workflow started on an orchestrator that used the prose-era fork ceremony and resumed on an orchestrator using the scripted ceremony must continue to work without changes to the state file. The script writes the same `modelSelections` entries as the prose-era ceremony (same schema, same fields), so mid-workflow resume is transparent.

## Dependencies

- **FEAT-020 — Plugin-Shared Scripts Library Foundation**: Already merged (confirmed on `main` — `plugins/lwndev-sdlc/scripts/` ships ten scripts plus a `tests/` directory and `README.md`). `prepare-fork.sh` is installed into the existing directory as an eleventh sibling; no directory-creation logic is required in this PR.
- **FEAT-014 — Adaptive Model Selection**: This feature depends on `workflow-state.sh resolve-tier` and `record-model-selection` subcommands shipping in FEAT-014 (already merged at the time of writing). No new behavior is introduced — `prepare-fork.sh` is a composite.

No new runtime dependencies beyond what `workflow-state.sh` already requires (`bash`, `jq`, `date`).

## Edge Cases

1. **State file missing**: exit `2` with diagnostic. The orchestrator must have already run `workflow-state.sh init` before invoking any fork-step, so a missing state file at this point is a bug in the orchestrator's procedure, not a user-visible failure mode. The script's error message points at the expected path.

2. **`jq` missing**: exit `4`. `jq` is expected to be present because `workflow-state.sh` requires it; but if the user's environment broke after workflow init, the script must fail cleanly rather than silently omitting the `complexityStage` / `complexity` / `modelOverride` fields from step 3 and step 4.

3. **`resolve-tier` returns a tier below baseline** (Edge Case 11 / hard-override-below-baseline): script emits both the non-locked echo line **and** the Edge Case 11 warning line on stderr. Exit code remains `0`. The user explicitly asked for the downgrade via `--cli-model`, so the script does not block.

4. **`--mode` passed for a non-reviewing-requirements skill**: exit `2`. The `record-model-selection` subcommand itself accepts any string for the `<mode>` slot, so the validation is purely a guard-rail to catch caller bugs early. Symmetric rule applies to `--phase` with non-implementing-plan-phases skills.

5. **`--mode` and `--phase` both passed**: exit `2` with `Error: --mode and --phase are mutually exclusive`. Current skill map has no step that takes both.

6. **`--cli-model-for` repeated**: the script accumulates every occurrence into an array and forwards each through to `resolve-tier`. `resolve-tier` walks the flag list in argv order: **the first flag whose step name matches the current target wins**; later flags for the same step are ignored. Flags for unrelated steps pass through silently without altering resolution. This applies whether the repeats target the same step (same-step disambiguation) or different steps (cross-step coverage in a single invocation). The script does not re-implement this logic — it only preserves all occurrences so the resolver can make the precedence decision.

7. **Subshell executing `prepare-fork.sh` cannot see `CLAUDE_PLUGIN_ROOT`**: the script falls back to deriving the root from its own path (FR-2 step 1). This path is deterministic because plugin-shared scripts live at `${CLAUDE_PLUGIN_ROOT}/scripts/prepare-fork.sh` by the FEAT-020 contract.

8. **Workflow state `complexity` field missing** (pre-FEAT-014 state file opened after the resume migration ran): `jq ... // "medium"` defaults to `medium` per the FEAT-014 FR-13 migration contract. No special handling needed.

9. **Baseline-locked step receives a hard override** (e.g., `--cli-model opus` with `finalizing-workflow`): `resolve-tier` returns `opus` per FEAT-014 FR-5 #2. `locked == "true"` still applies to the step, but the echo line is the **non-locked** variant because the override pushed the step off its baseline. Per SKILL.md's Edge Case 11 format, the override surfaces in the `override=` token. If the resolved tier is strictly below the step's baseline tier after the override, the Edge Case 11 warning line is also emitted. (Hard override + baseline-locked + below-baseline downgrade is theoretically possible only for `finalizing-workflow` / `pr-creation` receiving `--cli-model haiku` — a no-op in practice because those baselines are already `haiku`. But the logic must handle it.)

10. **Orchestrator invokes `prepare-fork.sh` from a nested shell** (not bash): the shebang `#!/usr/bin/env bash` forces bash regardless of the caller's shell. Test fixtures validate this by invoking the script from `zsh`.

## Testing Requirements

### Unit Tests

Add a bats fixture at `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` (matching the existing FEAT-020 layout — `plugins/lwndev-sdlc/scripts/tests/` holds all ten sibling bats fixtures today):

- **Arg validation** (exit `2`): missing positional args, unknown flags, non-numeric `stepIndex`, unknown `skill-name`, `--mode` on non-reviewing-requirements skill, `--phase` on non-implementing-plan-phases skill, both `--mode` and `--phase`.
- **SKILL.md resolution** (exit `3`): rename the target SKILL.md in a fixture and assert the error message names the resolved path.
- **Propagation** (exit `1`): feed an invalid step-name to `resolve-tier` through the script and assert the propagated exit and stderr.
- **State-file missing** (exit `2`): run the script without a matching state file.
- **`jq` missing** (exit `4`): temporarily `PATH=` a bin that omits `jq`; assert exit `4` and error message.
- **Happy path, non-locked**: create a state fixture, invoke for `reviewing-requirements` with `--mode standard`, assert:
  - stdout is exactly `sonnet\n` (or whatever the baseline resolves to).
  - stderr contains exactly one `[model]` line matching the non-locked regex.
  - The state file has a new `modelSelections` entry with the expected `skill`, `mode`, `phase`, `tier`, `complexityStage`, `startedAt`.
- **Happy path, baseline-locked**: invoke for `finalizing-workflow`, assert stderr `[model]` line is the baseline-locked format and contains no `wi-complexity=` / `override=` tokens.
- **Happy path, Edge Case 11**: invoke for `creating-implementation-plans` with `--cli-model haiku`, assert stderr contains both the non-locked line **and** the Edge Case 11 warning line.
- **Repeated `--cli-model-for`**: invoke with two `--cli-model-for` flags; assert both are forwarded (verify via injected `resolve-tier` wrapper or by checking stdout tier matches the expected resolution).
- **Non-bash caller**: invoke from `/bin/sh -c 'prepare-fork.sh ...'`; assert exit `0` and correct stdout.

### Integration Tests

Extend `scripts/__tests__/orchestrating-workflows.test.ts` (or its equivalent at the time of landing) with:

- End-to-end test: synthetic workflow state, invoke `prepare-fork.sh` directly for every step-name in the map, assert state-file `modelSelections` count = number of invocations.
- Round-trip test: take an existing pre-FEAT-021 workflow state file, resume on the new orchestrator, invoke `prepare-fork.sh`, assert the resulting `modelSelections` entries are schema-compatible with the pre-FEAT-021 entries (same keys, same types).

### Manual Testing

1. Run a full feature workflow end-to-end on a toy requirements doc. Verify:
   - The console shows ~10 `[model]` echo lines, one per fork.
   - The state-file `modelSelections` array grows by exactly 10 entries.
   - The resolved tiers match FEAT-014's expected outputs for a medium-complexity feature.
2. Pass `--model opus` as an orchestrator-level flag. Verify:
   - Every non-locked fork's `[model]` line shows `override=cli-model:opus`.
   - The two baseline-locked forks (`finalizing-workflow`, `pr-creation`) show `override=cli-model:opus` (hard overrides bypass the lock) and the tier is `opus`.
3. Pass `--model haiku` with `--model-for reviewing-requirements:opus`. Verify:
   - The two `reviewing-requirements` forks show `override=cli-model-for:opus` and tier `opus`.
   - Every other fork shows `override=cli-model:haiku` and tier `haiku`. Forks with baseline `sonnet` emit the Edge Case 11 warning line.
4. Forcibly kill a fork after `prepare-fork.sh` returns but before the Agent tool completes. Resume the workflow. Verify the orphan `modelSelections` entry is still present and the retry appends a new one (NFR-2).

## Acceptance Criteria

- [ ] `plugins/lwndev-sdlc/scripts/prepare-fork.sh` exists, is executable, has shebang `#!/usr/bin/env bash`, and implements FR-1 and FR-2.
- [ ] FR-6 holds: no existing `workflow-state.sh` subcommand changes behavior; no state-file schema field is added or modified; existing `scripts/__tests__/workflow-state.test.ts` passes unchanged except for the two new subcommand cases added for FR-3.
- [ ] FR-3 lands in the **same PR** as the script — `step-baseline` and `step-baseline-locked` subcommands are exposed on `workflow-state.sh`, and the new bats fixture invokes them via `prepare-fork.sh` end-to-end. Independent landing is not acceptable (FR-2 Step 4 depends on them).
- [ ] `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` exists and every test listed in "Unit Tests" passes, including a dedicated case for NFR-1's ordering invariant: force `step-baseline-locked` to fail (e.g. invoke with a synthetic unknown skill-name guarded past the script's own allowlist) and assert the prior `modelSelections` entry from FR-2 Step 3 is still present in the state file while the script's exit code reflects the child failure.
- [ ] The "Forked Steps" section of `orchestrating-workflows/SKILL.md` is rewritten per FR-4; the four prose sub-steps are replaced by the single scripted invocation; the PR-creation fork site explicitly passes `pr-creation` (not the state-file's `"orchestrator"` skill label) to `prepare-fork.sh` (see FR-1 PR-creation caveat).
- [ ] `references/model-selection.md` includes the FR-5 note.
- [ ] `plugins/lwndev-sdlc/scripts/README.md` script table includes a `prepare-fork.sh` row per FR-5.
- [ ] Manual test 1 (happy-path feature workflow) shows the expected console output and `modelSelections` entries.
- [ ] Manual tests 2 and 3 (CLI overrides) produce the documented echo-line variants.
- [ ] Manual test 4 (kill + resume) demonstrates the NFR-2 audit-trail preservation.
- [ ] No regression in existing orchestrator behavior — existing integration tests (`scripts/__tests__/orchestrating-workflows.test.ts`) pass unchanged after FR-4's SKILL.md rewrite.
- [ ] Measured token savings on a representative feature workflow show ≥ 3,000 tokens saved vs. the pre-FEAT-021 baseline. (Below the #181 estimate's low end is acceptable — the estimate is approximate; the structural win matters more than the exact count.)
