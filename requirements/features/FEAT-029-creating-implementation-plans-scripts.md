# Feature Requirements: `creating-implementation-plans` Scripts + Per-Phase Tier Reduction (Items 4.2–4.11)

## Overview
Collapse the deterministic prose inside `creating-implementation-plans` into five skill-scoped shell scripts, then couple that move-to-scripts work with a per-phase model-selection redesign so most phases of a typical feature workflow resolve to Haiku or Sonnet and Opus is reserved for phases that genuinely warrant it. The plan-time scripts (4.2–4.6) replace today's prose for plan-skeleton rendering, DAG validation, per-phase complexity scoring, split suggestion, and phase-size enforcement; the coupled tier-resolution changes (4.7–4.10) make `workflow-state.sh resolve-tier` per-phase aware, lower the `implementing-plan-phases` baseline from `sonnet` to `haiku`, thread `--phase N` through `prepare-fork.sh`, and replace the raw phase-count post-plan classifier with a per-phase `max`. The model-selection reference doc (4.11) is rewritten to reflect the new behaviour and to retire two known limitations.

## Feature ID
`FEAT-029`

## GitHub Issue
[#190](https://github.com/lwndev/lwndev-marketplace/issues/190)

## Priority
High — two compounding savings levers. (1) Prose-to-script for plan creation: ~550–750 tok per plan creation (4.2 + 4.3 scope). (2) Per-phase tier reduction is the bigger lever: a 4-phase feature where 3 phases qualify as low and 1 as medium drops fork cost from 4×Opus to 3×Haiku + 1×Sonnet — order-of-magnitude token-cost reduction on `implementing-plan-phases` fork calls for the typical workflow. NFR-4 from FEAT-014 ("fresh default invocation on a typical chore or low-severity bug produces zero Opus fork calls") extends to features whose phases are individually mechanical, which becomes the common case once size discipline is enforced at plan time. Cumulative wall-clock and dollar savings per feature workflow dominate the per-invocation savings.

## User Story
As the orchestrator (or a user manually invoking `/creating-implementation-plans`) authoring a multi-feature implementation plan, I want plan-skeleton rendering, DAG validation, per-phase complexity scoring, split suggestion, and phase-size enforcement to happen via single script calls, AND I want each `implementing-plan-phases` fork that the plan later spawns to resolve its own per-phase tier from the scored phase block, so that mechanical phases run on Haiku, schema/migration or multi-skill phases run on Sonnet or Opus on demand, and the `1→low / 2–3→medium / 4+→high` raw-phase-count anti-pattern (Edge Case 8 in `references/model-selection.md`) — where splitting a phase for clarity actively *upgrades* the tier — is replaced with a model where splitting *distributes* work across cheaper forks.

## Command Syntax

All plan-time scripts (4.2, 4.3, 4.4, 4.5, 4.6) live under `${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/` and follow the plugin-shared conventions established by #179 and the precedent set by FEAT-020 / FEAT-021 / FEAT-022 / FEAT-025 / FEAT-026 / FEAT-027 (shell-first, exit-code driven, stdout carries JSON or pure string, stderr for `[info]` / `[warn]` / error lines, bats-tested). Items 4.7–4.10 amend existing scripts (`workflow-state.sh`, `prepare-fork.sh`) under `${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/` and `${CLAUDE_PLUGIN_ROOT}/scripts/` respectively.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/render-plan-scaffold.sh" <FEAT-IDs> [--enforce-phase-budget]
bash "${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/validate-plan-dag.sh" <plan-file>
bash "${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/phase-complexity-budget.sh" <plan-file> [--phase N]
bash "${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/split-phase-suggest.sh" <plan-file> <phase-N>
bash "${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/validate-phase-sizes.sh" <plan-file>
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh" resolve-tier <ID> <step-N> <skill> [--phase N --plan-file <path>] [--cli-model <tier>] [--cli-complexity <tier>] [--cli-model-for <step>:<tier> ...]
bash "${CLAUDE_PLUGIN_ROOT}/scripts/prepare-fork.sh" <ID> <step-N> <skill> [--phase N --plan-file <path>] [--cli-model ...] [--cli-complexity ...] [--cli-model-for ...]
```

### Examples

```bash
# Render a plan skeleton for a single feature (default: phase-budget gate is warn-only)
bash "${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/render-plan-scaffold.sh" FEAT-029
# stdout: requirements/implementation/FEAT-029-creating-implementation-plans-scripts.md

# Render a plan skeleton for a multi-feature project, enforcing phase-size budgets
# (FEAT-030 here is hypothetical, used only to illustrate the multi-feature shape)
bash "${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/render-plan-scaffold.sh" FEAT-029,FEAT-030 --enforce-phase-budget
# stdout: requirements/implementation/FEAT-029-creating-implementation-plans-scripts.md

# Validate the DAG: no cycles, all "Depends on Phase N" references resolve
bash "${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/validate-plan-dag.sh" \
  requirements/implementation/FEAT-029-creating-implementation-plans-scripts.md
# stdout: ok

# Score every phase in the plan (no --phase: per-phase array)
bash "${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/phase-complexity-budget.sh" \
  requirements/implementation/FEAT-029-creating-implementation-plans-scripts.md
# stdout: [{"phase":1,"tier":"haiku","signals":{...},"overBudget":false}, ...]

# Score a single phase
bash "${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/phase-complexity-budget.sh" \
  requirements/implementation/FEAT-029-creating-implementation-plans-scripts.md --phase 3
# stdout: {"phase":3,"tier":"sonnet","signals":{...},"overBudget":false}

# Suggest a 2–3 phase split for an over-budget phase (advisory)
bash "${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/split-phase-suggest.sh" \
  requirements/implementation/FEAT-029-creating-implementation-plans-scripts.md 5
# stdout: {"original":5,"suggestions":[{"name":"...","steps":[1,2,3]},{"name":"...","steps":[4,5]}]}

# Gate: fail if any phase exceeds budget without an explicit override
bash "${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/validate-phase-sizes.sh" \
  requirements/implementation/FEAT-029-creating-implementation-plans-scripts.md
# stdout: ok | exit 0  (or exit 1 with a stderr listing of offending phases)

# Per-phase tier resolution from the orchestrator
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh" \
  resolve-tier FEAT-029 6 implementing-plan-phases \
  --phase 2 --plan-file requirements/implementation/FEAT-029-creating-implementation-plans-scripts.md
# stdout: haiku
```

## Functional Requirements

### FR-1 (Item 4.2): `render-plan-scaffold.sh` — Plan Skeleton Generator
- Signature: `render-plan-scaffold.sh <FEAT-IDs> [--enforce-phase-budget]`.
- `<FEAT-IDs>` is a comma-separated list of one or more `FEAT-NNN` IDs (e.g., `FEAT-029`, or `FEAT-029,FEAT-030,FEAT-031` where `FEAT-030`/`FEAT-031` are hypothetical examples for illustration). Whitespace around commas is tolerated.
- Resolve every ID via `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh "<FEAT-NNN>"` (item 4.1, shipped via #180). Exit `1` and surface `resolve-requirement-doc.sh` stderr verbatim on any unresolved ID.
- Read each resolved feature requirement document and pre-populate the plan skeleton's:
  - **Title**: `# Implementation Plan: <Primary Feature Name>` (primary = first ID in the list).
  - **Features Summary table**: one row per ID with columns `ID | Name | Priority | Complexity | Status`. `Name` and `Priority` come from the feature doc's `# Feature Requirements:` heading and `## Priority` section; `Complexity` is left as `TBD` (the model fills this in once phases are drafted); `Status` defaults to `Pending`.
  - **Phase blocks**: emit one `### Phase N: <placeholder>` block per FR (Functional Requirement) discovered in the source feature docs, in document order. Each phase block is pre-populated with a `**Status:** Pending` line, a `**Depends on:**` placeholder (model fills in the actual dependencies), an `#### Implementation Steps` placeholder list, and an `#### Deliverables` placeholder list. The model authors the actual phase content; the script generates the structural scaffold only.
- Output: write the rendered plan to `requirements/implementation/<primary-FEAT-ID>-<slug>.md`. Emit the absolute path on stdout.
- Exit `2` if the target file already exists (refuse to overwrite — use a separate `--force` flag in a future iteration if needed; out of scope for this feature).
- `--enforce-phase-budget` (optional): after rendering, invoke `validate-phase-sizes.sh` (FR-5) on the rendered plan as a gate. Without the flag, the size-gate is warn-only (FR-5 emits its `[warn]` lines but the script exits `0`); with the flag, FR-5's failure exit propagates and the script exits `1` with `[warn]` lines describing offending phases preserved. (Note: at scaffold time the model has not yet authored phase content, so the gate is typically used after the model fills in implementation steps and deliverables and the script is re-run with `--enforce-phase-budget`. See Edge Case 1 for the recommended caller pattern.)
- Exit codes: `0` on success; `1` on `resolve-requirement-doc.sh` failure, other I/O error, or `--enforce-phase-budget` gate failure (FR-5 propagation); `2` on missing args, malformed `FEAT-IDs` list, or target file already exists. Exit `1` is intentionally shared between upstream-resolver / I/O failures and gate failures — callers that need to distinguish must inspect stderr: `[warn] phase ...` lines indicate gate failure (FR-5 stderr format); other stderr content indicates resolver/I/O failure. A future iteration may reserve a distinct exit code for the gate-failure path; out of scope for this feature.
- Replaces `creating-implementation-plans/SKILL.md` Quick Start steps 3–5 prose for the deterministic skeleton work — ~400 tokens per plan.

### FR-2 (Item 4.3): `validate-plan-dag.sh` — Phase Dependency Graph Validation
- Signature: `validate-plan-dag.sh <plan-file>`.
- Exit `2` on missing arg; exit `1` on plan file not found / unreadable.
- Scan the plan for every `### Phase <N>: <name>` block. For each block, extract the `**Depends on:**` line (if present). Permitted forms:
  - `**Depends on:** Phase 1` (single)
  - `**Depends on:** Phase 1, Phase 3` (multiple)
  - `**Depends on:** none` or omission of the line entirely → no dependencies (the phase is implicitly unblocked from the start of the plan).
- Build the dependency graph in-memory and run two checks:
  1. **No cycles**: detect cycles via topological sort (Kahn's algorithm). On cycle detection, emit `error: cycle detected involving phases <N>, <M>, ...` to stderr and exit `1`.
  2. **All references resolve**: every `Phase <N>` token in a `**Depends on:**` line must reference a phase that exists in the plan. On unresolved reference, emit `error: phase <N> depends on non-existent phase <M>` to stderr and exit `1`. Forward references (Phase 1 depending on Phase 5) are syntactically valid; the cycle check catches the only practical problem (a literal cycle).
- Stdout on success: `ok`. Exit `0`.
- Fence-aware: `**Depends on:**` lines inside fenced code blocks (```` ``` ```` / ```` ~~~ ````) are skipped. This matters because the plan template and reference docs include example `**Depends on:**` lines inside fenced blocks (documentation of the canonical format) — those must never be parsed as real dependencies.
- Exit codes: `0` on `ok`; `1` on cycle, unresolved reference, or I/O error; `2` on missing arg.
- Replaces the corresponding "verification checklist" item in `creating-implementation-plans/SKILL.md` — ~150 tokens per plan.

### FR-3 (Item 4.4): `phase-complexity-budget.sh` — Per-Phase Tier Scoring
- Signature: `phase-complexity-budget.sh <plan-file> [--phase N]`.
- Exit `2` on missing arg or malformed `--phase N` (must be a positive integer); exit `1` on plan file not found / unreadable / no `### Phase` blocks present.
- For each phase block (or only the requested phase when `--phase N` is supplied), compute the four signals defined in the budget table and aggregate them into a final tier per the algorithm below.

**Per-phase budget signals** (initial proposal, tunable in one table at the top of the script):

| Signal | Source | Low (haiku) | Medium (sonnet) | High (opus) |
|--------|--------|------------:|----------------:|------------:|
| Implementation steps | Count of `^[0-9]+\.` lines inside the phase's `#### Implementation Steps` subsection | ≤3 | 4–7 | 8+ |
| Deliverables | Count of `- \[[ x]\]` lines inside the phase's `#### Deliverables` subsection | ≤4 | 5–9 | 10+ |
| Distinct files touched | Unique backticked paths (matching `` `<path>` ``) extracted from deliverable lines | ≤3 | 4–8 | 9+ |
| Heuristic flags | Substring scan of the phase block (case-insensitive) for tokens listed below | none | `schema` / `migration` / `test infra` (`+1 tier each`) | `public api` / `security` / `multi-skill refactor` (`+1 tier each`) |

**Aggregation rule**: each signal independently maps to a tier. Final tier = `max` of the four component tiers, then apply heuristic-flag bumps (each `+1 tier` heuristic match upgrades the tier by one step in the `haiku < sonnet < opus` ordering, capped at `opus`). Multiple flag matches stack but cap at `opus`.

**Override clamp**: if the phase block contains a literal `**ComplexityOverride:** <tier>` line (where `<tier>` is one of `haiku`, `sonnet`, `opus`), the override **replaces** the computed tier outright (hard override at the per-phase level). The override line is fence-aware (skip if inside a fenced code block).

- Stdout shape:
  - With `--phase N`: a single JSON object: `{"phase":<N>,"tier":"haiku|sonnet|opus","signals":{"steps":<int>,"deliverables":<int>,"files":<int>,"flagsLow":[...],"flagsHigh":[...]},"overBudget":<bool>,"override":<tier|null>}`. `overBudget` is `true` if any single signal independently scored `opus` (high) without an override clamping it down — a forward-looking "this phase is genuinely complex, consider splitting" signal.
  - Without `--phase`: a JSON array of the same shape, one entry per phase, in document order.
- Exit codes: `0` on success; `1` on plan I/O error or no phase blocks; `2` on missing arg or malformed `--phase`.
- Pure read: this script never writes the plan file. It is safe to call repeatedly.

### FR-4 (Item 4.5): `split-phase-suggest.sh` — Advisory Phase Splitter
- Signature: `split-phase-suggest.sh <plan-file> <phase-N>`.
- Exit `2` on missing args or malformed `<phase-N>`; exit `1` on plan file not found / unreadable / phase block missing.
- Read the requested phase block. Group the implementation steps into 2–3 contiguous chunks that:
  - Preserve original step ordering (no reordering of steps).
  - Preserve any explicit "Depends on Step N" annotations within the phase (split boundary cannot place a step before its prerequisite).
  - Aim for roughly equal per-chunk step counts (within ±1 step).
  - Default to a 2-way split if the phase has 4–7 steps; default to a 3-way split if the phase has 8+ steps.
- For each chunk, propose a `name` (derived heuristically from the first step's verb + a noun extracted from the deliverable list) and emit the chunk's step indices.
- Stdout: a single JSON object: `{"original":<phase-N>,"suggestions":[{"name":"<chunk-name>","steps":[<idx>,<idx>,...]},{...}]}`. Suggestion names are inevitably crude (the model authors the final names); the script's job is to propose a viable cut, not the final wording.
- **Advisory only**: this script never writes the plan file. The orchestrator (or the model directly) reads the JSON and authors the actual split in the plan document.
- Exit codes: `0` on success (even if the split is heuristic-best-effort); `1` on plan I/O error; `2` on missing args.
- Stays prose: the judgment call on whether a proposed split is *semantically* sensible (e.g., does splitting at this boundary keep TDD pairing intact?) — that remains the model's responsibility.

### FR-5 (Item 4.6): `validate-phase-sizes.sh` — Phase-Size Gate
- Signature: `validate-phase-sizes.sh <plan-file>`.
- Exit `2` on missing arg; exit `1` on plan I/O error.
- Invoke `phase-complexity-budget.sh <plan-file>` (FR-3) internally and inspect the per-phase JSON array. A phase **fails the gate** when:
  - `overBudget == true` (any single signal independently scored `opus`)
  - AND the phase has no `**ComplexityOverride:** <tier>` line clamping it.
- For each failing phase, emit `[warn] phase <N>: over budget — <signal>=<value> exceeds <tier> threshold; either split (see split-phase-suggest.sh) or add **ComplexityOverride:** opus to the phase block.` to stderr.
- Stdout on success (no failing phases): `ok`. Exit `0`.
- Stdout on failure (one or more failing phases): nothing on stdout; stderr lists every offending phase. Exit `1`.
- Designed as the last step of `render-plan-scaffold.sh` (FR-1, when `--enforce-phase-budget` is passed) and as a verification-checklist item in the rewritten `creating-implementation-plans/SKILL.md`. The two callers reuse the same script.
- Note: this script is not a substitute for FR-2's `validate-plan-dag.sh`. DAG validation (correctness) and size validation (discipline) are independent gates and both run.

### FR-6 (Item 4.7): `workflow-state.sh resolve-tier` — Per-Phase Tier Resolution
- Amend the existing `resolve-tier` subcommand to accept two new optional flags: `--phase N` and `--plan-file <path>`. Both must be supplied together; supplying only one is an error (exit `2`).
- When both flags are present AND the `<skill>` argument is `implementing-plan-phases`:
  - Internally invoke `phase-complexity-budget.sh <plan-file> --phase <N>` (FR-3) to obtain the per-phase tier.
  - Use the per-phase tier as the **work-item complexity axis** input (Axis 2 in `references/model-selection.md`), in place of the workflow-level `complexity` value persisted in state.
  - The override chain (Axis 3 — CLI overrides, state `modelOverride`) walks unchanged. The per-phase tier replaces only the work-item complexity input, not the override chain.
- When `--phase` and `--plan-file` are both absent, behaviour is unchanged (the existing workflow-level `complexity` value is used).
- When `--phase`/`--plan-file` are present but `<skill>` is **not** `implementing-plan-phases`, the flags are accepted but ignored, and a `[info] resolve-tier: --phase ignored for non-phase skill <skill>` line is emitted to stderr. (Defensive — keeps the orchestrator's call-site simple.)
- Persist the per-phase tier in `modelSelections[step-N][phase-N]` alongside the existing per-step entry. The existing `phase` field on `modelSelections` continues to record which phase the entry belongs to; the new per-phase tier is keyed under that.
- Exit codes: `0` on success; `2` on malformed flag combinations.

### FR-7 (Item 4.8): Lower `implementing-plan-phases` Baseline to Haiku
- In `workflow-state.sh::_step_baseline` (the function that maps a `<skill>` name to its baseline tier), change the entry for `implementing-plan-phases` from `sonnet` to `haiku`.
- Sonnet/Opus resolution for `implementing-plan-phases` forks now comes entirely from per-phase classification (FR-3 + FR-6), not from a blanket floor.
- Keep the existing upgrade-only override chain semantics — soft overrides (`--complexity`, state `modelOverride`) still push the resolved tier up; hard overrides still bypass.
- The `implementing-plan-phases` step is **not** baseline-locked (unlike `finalizing-workflow` and PR creation). The work-item complexity axis remains active for it; only the floor changes.

### FR-8 (Item 4.9): `prepare-fork.sh` — Thread `--phase N` Through to `resolve-tier`
- Amend `prepare-fork.sh` to accept and forward two new optional flags: `--phase N` and `--plan-file <path>`. The orchestrator passes them when forking `implementing-plan-phases` for phase N of a plan; both flags forward verbatim into the internal `workflow-state.sh resolve-tier` call.
- Other forked steps (`reviewing-requirements`, `creating-implementation-plans`, `executing-chores`, etc.) are unaffected: when the orchestrator forks them, it does not pass `--phase`/`--plan-file`, and `prepare-fork.sh` continues to behave as today.
- The FR-14 console echo line emitted by `prepare-fork.sh` for `implementing-plan-phases` SHOULD include the phase number for traceability — proposed format: `[model] step <N> (implementing-plan-phases) → <tier> (workflow=<complexity>, phase=<phase-N>=<phase-tier>)`. The Unicode `→` is the documented emitter format; do not rewrite to ASCII.

### FR-9 (Item 4.10): Post-Plan Classifier — `max` of Per-Phase Tiers
- In `workflow-state.sh::classify-post-plan` (the function called by the orchestrator after `creating-implementation-plans` completes), replace the existing raw-phase-count mapping (`1→low`, `2–3→medium`, `4+→high`) with the following:
  - Invoke `phase-complexity-budget.sh <plan-file>` (FR-3) on the freshly-authored plan.
  - Compute the `max` of all phase tiers in the returned array.
  - Persist that `max` value as the workflow's post-plan `complexity`, with `complexityStage = post-plan` (semantics unchanged from FEAT-014 FR-2b).
- Splitting a phase no longer upgrades the workflow's complexity; it distributes the implementation work across cheaper per-phase forks. Splitting a phase only upgrades the workflow's complexity if one of the resulting sub-phases independently scores higher than every other phase (which is rare — a split usually produces two equally-mechanical halves).
- Honour the existing upgrade-only invariant (FEAT-014 FR-2b — Post-Plan Upgrade for Features; FR-12 enforces this same invariant on resume): the post-plan classifier may upgrade the workflow's `complexity` but never downgrade it. If `max(per-phase tiers)` is *lower* than the persisted init-stage `complexity`, the persisted value wins. (Reasoning: the init-stage classifier saw the requirement document, which encodes signals the phase-level scorer cannot see — e.g., FR count, security/compliance flags. Honouring the higher value preserves Edge Case 11 / NFR-4 contract from FEAT-014.)

### FR-10 (Item 4.11): Rewrite `references/model-selection.md`
- Rewrite the "Feature post-plan signal extractor" section under the "Axis 2 — Work-item complexity signal matrix" heading to document the per-phase classification path: link to FR-3 (`phase-complexity-budget.sh`), explain the `max`-of-per-phase-tiers rule (FR-9), and document the per-phase override line (`**ComplexityOverride:** <tier>`).
- Rewrite the **Known Limitation** bullet that combines (a) the `implementing-plan-phases` Haiku floor and (b) the per-phase-classification gap (the "Phased feature workflows currently bind every phase to a single feature-level tier" framing in the Edge Case 8 discussion). The two concerns are documented as a single combined bullet today; replace it with two distinct entries: (1) a brief note that per-phase classification is now first-class for `implementing-plan-phases` forks (link to FR-6 + FR-9), and (2) a re-framed entry describing the new explicit per-phase floor (`haiku`) that per-phase classification can upgrade (link to FR-7).
- Update the "Tuning the baseline matrix" cautionary note (currently "Do not drop `implementing-plan-phases` below `sonnet`"): re-frame from a hard "do not drop below sonnet" caution to a per-phase-floor explanation that points to FR-3 + FR-6. After FR-7 ships, the prior caution is actively wrong; the new caution should explain that `implementing-plan-phases` baselines at `haiku` and is upgraded per-phase via the FR-3 scorer.
- Add a brief migration note describing the contract change for the `modelSelections` shape (per-phase keying under `modelSelections[step-N]`) for any downstream consumers.

## Output Format

`render-plan-scaffold.sh`:
```text
requirements/implementation/FEAT-029-creating-implementation-plans-scripts.md
```

`validate-plan-dag.sh`:
```text
ok
```
On failure (stderr):
```text
error: cycle detected involving phases 2, 4, 7
```

`phase-complexity-budget.sh` (with `--phase`):
```json
{
  "phase": 3,
  "tier": "sonnet",
  "signals": {
    "steps": 5,
    "deliverables": 7,
    "files": 4,
    "flagsLow": ["schema"],
    "flagsHigh": []
  },
  "overBudget": false,
  "override": null
}
```

`phase-complexity-budget.sh` (no `--phase`):
```json
[
  {"phase":1,"tier":"haiku","signals":{...},"overBudget":false,"override":null},
  {"phase":2,"tier":"haiku","signals":{...},"overBudget":false,"override":null},
  {"phase":3,"tier":"sonnet","signals":{...},"overBudget":false,"override":null}
]
```

`split-phase-suggest.sh`:
```json
{
  "original": 5,
  "suggestions": [
    {"name": "Scaffold + Status Marker", "steps": [1, 2, 3]},
    {"name": "Verification + Commit", "steps": [4, 5]}
  ]
}
```

`validate-phase-sizes.sh`:
```text
ok
```
On failure (stderr):
```text
[warn] phase 3: over budget — steps=9 exceeds opus threshold; either split (see split-phase-suggest.sh) or add **ComplexityOverride:** opus to the phase block.
```

`workflow-state.sh resolve-tier --phase N --plan-file <path>`:
```text
haiku
```

`prepare-fork.sh` console echo (FR-14 format extended for per-phase context):
```text
[model] step 6 (implementing-plan-phases) → haiku (workflow=high, phase=2=haiku)
```

## Non-Functional Requirements

### NFR-1: Performance
- All five plan-time scripts (FR-1 to FR-5) must complete in under 1 second for plans up to 20 phases. They are pure-shell + standard utilities; no external network calls.
- `phase-complexity-budget.sh` is invoked twice per workflow at minimum (once at plan-creation time via FR-9, once per `implementing-plan-phases` fork via FR-6). It must be cheap enough that this is not a concern; cache the parse if needed within a single invocation but do not persist a cache to disk.
- `prepare-fork.sh` overhead must not regress: the new `--phase`/`--plan-file` forwarding adds at most one additional `bash` subprocess invocation (the internal `phase-complexity-budget.sh` call), and only for `implementing-plan-phases` forks.

### NFR-2: Error Handling
- Every script follows the plugin-shared exit-code conventions: `0` on success, `1` on I/O / runtime error (file not found, malformed plan structure, unresolved reference), `2` on usage error (missing arg, malformed flag combination).
- All `[warn]` and `[info]` lines emitted to stderr are tagged structured logs (Lite-narration carve-out: emit verbatim).
- `resolve-requirement-doc.sh` failures inside `render-plan-scaffold.sh` (FR-1) must surface upstream stderr verbatim — do not paraphrase.
- Cycle detection in `validate-plan-dag.sh` (FR-2) must list every phase involved in the cycle, not just the first one detected. This helps the model author the fix in one pass.
- The post-plan classifier (FR-9) must continue to emit the existing `[model] Work-item complexity upgraded since last invocation: <old> → <new>. Audit trail continues.` stderr line whenever a tier upgrade is persisted (FEAT-014 FR-2b contract — upgrade-only at post-plan stage; FR-12 enforces the same invariant on resume).

### NFR-3: Bats Test Coverage
- Each new script (FR-1 to FR-5) ships with a `*.bats` suite next to it under `${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/tests/`. The suite covers happy path, every documented exit code, fence-awareness for FR-2 / FR-3 / FR-5, and the `--phase` / `--enforce-phase-budget` flag forms.
- Amendments to existing scripts (FR-6 to FR-9) extend the existing bats suites under `${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/tests/` and `${CLAUDE_PLUGIN_ROOT}/scripts/tests/`. New behaviours include: `--phase N --plan-file <path>` forwarding for `prepare-fork.sh` and `resolve-tier`; the `[info] resolve-tier: --phase ignored for non-phase skill ...` line; the `max`-of-per-phase-tiers post-plan classifier; the upgrade-only invariant when `max` is lower than persisted init complexity.

### NFR-4: SKILL.md Lean-ness
- `creating-implementation-plans/SKILL.md` Quick Start steps 3–5 collapse from prose into single-line invocations of FR-1 / FR-2 / FR-5. The Verification Checklist gains one new item (`validate-phase-sizes.sh`) and updates the existing DAG-validation item to reference FR-2 by name.
- The skill's load-bearing carve-outs section (Output Style) is unchanged.
- `implementing-plan-phases/SKILL.md` does **not** need prose changes — it never referenced the `_step_baseline` directly. The tier resolution is entirely in the orchestrator's pre-fork path (FR-6 + FR-8).
- Net SKILL.md token reduction (creating-implementation-plans): ~550–750 tok per plan creation.

### NFR-5: Backward Compatibility
- Plans authored before this feature ships (without per-phase `**ComplexityOverride:**` lines and without explicit `**Depends on:**` lines) MUST continue to work. `phase-complexity-budget.sh` (FR-3) treats absence of an override as "no clamp"; `validate-plan-dag.sh` (FR-2) treats absence of a `**Depends on:**` line as "no dependencies" (implicit sequential ordering, matching today's model behaviour).
- Existing state files (created before FR-6 ships) lack per-phase keying under `modelSelections[step-N]`. The schema migration for this is identical to FEAT-014 FR-13 (silent in-place migration on first read) — the per-phase entry is added on first FR-6 invocation; pre-existing entries are untouched.
- The post-plan classifier change (FR-9) is upgrade-only (NFR-2). Workflows already paused at the plan-approval pause point (FEAT-014 Edge Case for resume) MUST continue to resume cleanly: the classifier re-runs against the now-existing plan file on resume; any tier upgrade is logged via the existing `[model] Work-item complexity upgraded since last invocation` line.

### NFR-6: Documentation Drift
- The `references/model-selection.md` rewrite (FR-10) is the single source of truth for the new behaviour. Cross-references from other reference docs (`references/step-execution-details.md`, `references/forked-steps.md`) should link to the rewritten section, not duplicate the prose.
- The README in `${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/` (and any plugin-level README that lists scripts) MUST list the five new scripts (FR-1 to FR-5) with their one-line purposes, mirroring the existing convention used for FEAT-027's six new scripts.

## Dependencies

- **#180** (`resolve-requirement-doc.sh` and the plugin-shared foundation library) — `render-plan-scaffold.sh` (FR-1) calls `resolve-requirement-doc.sh` to resolve `FEAT-NNN` IDs to file paths. #180 must merge first.
- **#181** (`prepare-fork.sh`) — FR-8 amends `prepare-fork.sh`. Sequencing matters: #181 ships the script; this feature extends it.
- **FEAT-014** (adaptive model selection) — every change here builds on the override chain, complexity axis, baseline matrix, and `modelSelections` persistence introduced by FEAT-014. The post-plan classifier (FR-9), upgrade-only invariant (FR-9 + NFR-2), and override-chain walking (FR-6) all extend FEAT-014's contracts.
- **FEAT-021** (`prepare-fork.sh` skeleton) — FR-8 modifies the file delivered by FEAT-021.
- **FEAT-026 / FEAT-027** — the script conventions, bats-coverage convention, and `[info]` / `[warn]` / `[model]` tagged-log convention are inherited verbatim. No reference changes; conventions are stable.

## Edge Cases

1. **`render-plan-scaffold.sh` invoked at scaffold time with `--enforce-phase-budget`**: at scaffold time, phase blocks are placeholders — the model has not yet authored implementation steps and deliverables. Running the gate then would fail every phase trivially (no signals to score). Recommended caller pattern: invoke `render-plan-scaffold.sh <FEAT-IDs>` first (no flag), let the model fill in phase content, then invoke `validate-phase-sizes.sh <plan-file>` directly as the verification step. The skill's rewritten Verification Checklist documents this as the canonical pattern. (Re-invoking `render-plan-scaffold.sh ... --enforce-phase-budget` against an already-rendered plan would exit `2` per FR-1's overwrite-refusal rule, so the gate would never run that way — `validate-phase-sizes.sh` is the only correct caller for the rerun-the-gate scenario.)
2. **DAG with explicit forward dependency**: `Phase 1` declares `**Depends on:** Phase 5`. `validate-plan-dag.sh` (FR-2) treats this as syntactically valid (no cycle) but the orchestrator's `next-pending-phase.sh` (FEAT-027 FR-1) will refuse to start Phase 1 until Phase 5 completes. This is intentional — explicit out-of-order dependencies are sometimes necessary for shared-infrastructure phases.
3. **A phase has zero implementation steps and zero deliverables**: `phase-complexity-budget.sh` (FR-3) scores it as `haiku` (all signals at the lowest tier), `overBudget=false`. `validate-phase-sizes.sh` (FR-5) passes. This is fine — empty phases are typically placeholders that the model expanded later or pure-prose phases (e.g., a "Documentation" phase that produces no executable artifacts).
4. **A phase has 30+ steps**: `phase-complexity-budget.sh` scores `opus`, `overBudget=true`. `validate-phase-sizes.sh` fails the gate. The user runs `split-phase-suggest.sh` (FR-4) to get a 3-way split proposal, authors the actual split in the plan, and re-runs `validate-phase-sizes.sh`. If the user disagrees with the gate's judgement, they add a `**ComplexityOverride:** opus` line to the phase block; the gate then passes.
5. **Heuristic-flag false positive**: a phase block contains the substring "schema" in unrelated context (e.g., "this phase does not modify the database schema"). FR-3 still bumps the tier on the substring match. Mitigation: the per-phase `**ComplexityOverride:** <tier>` line is the explicit escape hatch (clamps the tier outright). False positives are an acceptable cost of the keyword-scan heuristic; tighter NLP is out of scope.
6. **Heuristic-flag stacking exceeds `opus`**: a phase matches both `schema` and `public api`. Both bumps stack but the tier caps at `opus` (FR-3 aggregation rule). No regression — this is the documented behaviour.
7. **`split-phase-suggest.sh` against a 1-step phase**: cannot meaningfully split. FR-4 emits `{"original":<N>,"suggestions":[]}` with exit `0`. Caller (model or orchestrator) sees the empty suggestions array and either accepts the phase as-is (perhaps with `**ComplexityOverride:** sonnet`) or restructures more substantially.
8. **Post-plan classifier downgrade**: a feature classified `high` at init time (e.g., 12 functional requirements + security flag) produces a 4-phase plan whose phases all individually score `haiku`. `max(haiku, haiku, haiku, haiku) = haiku`, but the persisted init complexity is `high`. NFR-5 (upgrade-only invariant) keeps the persisted `high` — the workflow continues to resolve `reviewing-requirements`, `documenting-qa`, etc. at `high` (Sonnet/Opus). Only the per-phase forks resolve at `haiku` (FR-6). Reasoning: the init-stage signals (FR count, security flag) reflect cross-cutting concerns that the per-phase scorer cannot see.
9. **Per-phase tier when plan file is missing / unreadable**: FR-6 invokes `phase-complexity-budget.sh` internally; if that exits non-zero, FR-6 falls back to the workflow-level `complexity` value (existing behaviour) and emits `[warn] resolve-tier: phase-complexity-budget failed for phase <N>; falling back to workflow complexity <tier>.` to stderr. The fork still runs; degraded gracefully. The same fallback applies to the post-plan classifier path in FR-9: when `phase-complexity-budget.sh` exits non-zero during `classify-post-plan` (malformed plan, no `### Phase` blocks, file unreadable), the persisted init-stage `complexity` is preserved unchanged, a `[warn] classify-post-plan: phase-complexity-budget failed; preserving init-stage complexity <tier>.` line is emitted to stderr, and the workflow continues. This matches the existing upgrade-only invariant from FEAT-014 FR-2b — failure to compute a new value never downgrades the persisted value.
10. **Multi-feature plan rendered from `render-plan-scaffold.sh FEAT-029,FEAT-030`** (FEAT-030 is a hypothetical example here): FR-1 emits one Features Summary table row per ID and one phase block per FR found in *any* of the source documents (in order: all of FEAT-029's FRs, then all of the second feature's FRs). The model is expected to consolidate phases that span multiple features — that is judgment work, not script work.
11. **`**Depends on:**` line listing a non-`Phase N` token** (e.g., `**Depends on:** PR #123 merging`): FR-2 ignores tokens that don't match `Phase <N>`. Free-text rationale lines coexist with the strict dependency parser.
12. **`workflow-state.sh resolve-tier` invoked without `--phase` for `implementing-plan-phases`**: FR-6 falls back to the workflow-level `complexity` value (Axis 2 unchanged). This preserves backward compatibility for any caller that hasn't been updated to pass `--phase`. The orchestrator's `prepare-fork.sh` (FR-8) is the canonical caller and always passes `--phase` for `implementing-plan-phases` forks; manual invocations may omit it.

## Testing Requirements

### Unit Tests (bats)
- `render-plan-scaffold.sh.bats`: happy path single feature, happy path multi-feature, exit `1` on `resolve-requirement-doc.sh` failure, exit `2` on missing arg / malformed `FEAT-IDs` / target file already exists, `--enforce-phase-budget` flag forwarding to FR-5.
- `validate-plan-dag.sh.bats`: happy path (valid DAG → `ok`), cycle detection (3-cycle, 5-cycle), unresolved reference detection, fence-awareness (example `**Depends on:**` inside fenced block ignored), absence of `**Depends on:**` line treated as no dependencies.
- `phase-complexity-budget.sh.bats`: happy path per-phase, happy path full plan, every signal threshold boundary (steps 3/4, 7/8; deliverables 4/5, 9/10; files 3/4, 8/9), heuristic flag matches (low: `schema`, `migration`, `test infra`; high: `public api`, `security`, `multi-skill refactor`), heuristic stacking caps at `opus`, `**ComplexityOverride:**` clamp (haiku, sonnet, opus), `overBudget` true/false, exit `1` on no phase blocks, exit `2` on missing arg / malformed `--phase`.
- `split-phase-suggest.sh.bats`: happy path (4-step → 2-way, 8-step → 3-way), 1-step → empty suggestions, ordering preservation, `**Depends on Step N**` honouring (split boundary refuses to place a step before its prerequisite).
- `validate-phase-sizes.sh.bats`: happy path (no overBudget phases → `ok`), failure path (one overBudget phase → exit `1` + stderr listing), `**ComplexityOverride:**` clamp passes the gate.
- `workflow-state.sh resolve-tier` extension: per-phase tier resolution path, `--phase` ignored for non-phase skills (`[info]` line emitted), `--phase` without `--plan-file` exits `2`, `--plan-file` without `--phase` exits `2`, persistence under `modelSelections[step-N][phase-N]`.
- `prepare-fork.sh` extension: `--phase`/`--plan-file` forwarding for `implementing-plan-phases`, FR-14 console echo line includes `phase=<N>=<tier>` suffix, other forked skills unaffected.
- `workflow-state.sh classify-post-plan` extension: `max`-of-per-phase-tiers semantics, upgrade-only invariant honoured (init `high` + per-phase `max(haiku,haiku) = haiku` → persisted complexity stays `high`).

### Integration Tests
- End-to-end on a synthetic 4-phase plan where 3 phases qualify as `haiku` and 1 as `sonnet`: `prepare-fork.sh` resolves to the correct per-phase tier on each invocation; `[model] step ... phase=<N>=<tier>` echo line is present in stderr; `modelSelections` state correctly records per-phase entries.
- Graceful degradation: simulate `phase-complexity-budget.sh` failure inside `resolve-tier`; the fork still runs at the workflow-level `complexity` tier; `[warn] resolve-tier: phase-complexity-budget failed ...` is emitted.
- Resume flow: pause a workflow at the plan-approval pause point, edit a phase's `**ComplexityOverride:**` line in the plan file, resume. The post-plan classifier re-runs, the per-phase tier reflects the override, and `[model] Work-item complexity upgraded ...` is emitted only if the override actually upgrades the workflow `max`.

### Manual Testing
- Run the orchestrating-workflows skill against a real feature (this one — FEAT-029) end to end. Confirm: `phase-complexity-budget.sh` scores produce sensible tier assignments; `validate-phase-sizes.sh` either passes or surfaces actionable warnings; per-phase forks use the resolved tiers (cross-check via `[model]` echo lines); total Opus minutes spent on the feature workflow are visibly reduced versus a pre-FEAT-029 baseline (at least one phase resolves below Opus).

## Future Enhancements
- `--force` flag on `render-plan-scaffold.sh` to overwrite an existing plan file. Out of scope for this feature; default refusal is the safer behaviour.
- Tighter NLP for heuristic flags in `phase-complexity-budget.sh` (e.g., negation detection — ignore "this phase does not modify the schema"). Out of scope; the explicit override line is the escape hatch.
- A reverse pass: `phase-merge-suggest.sh` for trivially-tiny phases that could be combined to amortise per-fork overhead. Out of scope; per-phase forks are cheap enough on Haiku that the savings are marginal.
- Persisting `phase-complexity-budget.sh` results to a sidecar cache under `.sdlc/cache/phase-budget-<plan-hash>.json` to avoid re-computing on every fork. Out of scope; current performance is well under NFR-1 budget.

## Acceptance Criteria
- [ ] FR-1: `render-plan-scaffold.sh` exists with full bats coverage, supports single and multi-feature inputs, refuses to overwrite, supports `--enforce-phase-budget`.
- [ ] FR-2: `validate-plan-dag.sh` exists with full bats coverage; detects cycles and unresolved references; is fence-aware.
- [ ] FR-3: `phase-complexity-budget.sh` exists with full bats coverage; supports per-phase and full-plan modes; honours `**ComplexityOverride:**` clamps; documents the budget table at the top of the script for tuning.
- [ ] FR-4: `split-phase-suggest.sh` exists with full bats coverage; preserves step ordering and `**Depends on Step N**` annotations; emits advisory JSON without writing the plan.
- [ ] FR-5: `validate-phase-sizes.sh` exists with full bats coverage; integrates as the last step of FR-1 when `--enforce-phase-budget` is passed; integrates as a verification-checklist item in the rewritten SKILL.md.
- [ ] FR-6: `workflow-state.sh resolve-tier` accepts `--phase N --plan-file <path>`; per-phase tier replaces the workflow-complexity input for `implementing-plan-phases` forks; bats coverage for happy path + every malformed-flag exit; `modelSelections` schema extended.
- [ ] FR-7: `implementing-plan-phases` baseline lowered to `haiku`; existing override chain semantics unchanged; bats coverage updated.
- [ ] FR-8: `prepare-fork.sh` forwards `--phase`/`--plan-file` to `resolve-tier` for `implementing-plan-phases` forks; FR-14 console echo line includes `phase=<N>=<tier>`; bats coverage extended.
- [ ] FR-9: post-plan classifier replaced with `max`-of-per-phase-tiers; upgrade-only invariant honoured; bats coverage extended.
- [ ] FR-10: `references/model-selection.md` rewritten — Edge Case 8 limitation retired, Haiku-floor limitation re-framed, migration note added, cross-references to FR-3 / FR-6 / FR-9 included.
- [ ] `creating-implementation-plans/SKILL.md` Quick Start collapses to single-line script invocations; Verification Checklist updated.
- [ ] All amendments to `workflow-state.sh` and `prepare-fork.sh` ship with extended bats coverage in their existing test suites.
- [ ] End-to-end manual test on a 4-phase synthetic plan demonstrates per-phase tier resolution working through the full pre-fork ceremony.
- [ ] NFR-5 verified: a pre-existing state file (created before FR-6 ships) loads cleanly without manual migration; a pre-existing plan without `**ComplexityOverride:**` lines validates without warnings under FR-3 / FR-5.
- [ ] NFR-6 verified: cross-references in `references/step-execution-details.md` and `references/forked-steps.md` are updated to point to the rewritten `references/model-selection.md` section; the `creating-implementation-plans/README` (or plugin-level README) lists FR-1 through FR-5 scripts with one-line purposes.
