# Feature Requirements: Adaptive Model Selection for Forked Subagents

## Overview

Update the `orchestrating-workflows` skill so each forked subagent step selects its model adaptively based on the inherent demands of the step and the complexity of the work item, rather than silently inheriting the parent conversation's model. Mechanical steps (finalize, PR creation) default to Haiku, most validation/execution steps default to Sonnet, and only high-complexity features bump to Opus.

## Feature ID
`FEAT-014`

## GitHub Issue
[#130](https://github.com/lwndev/lwndev-marketplace/issues/130)

## Priority
High - Eliminates silent Opus over-provisioning across every chore, bug, and minor feature chain, reducing token cost by an order of magnitude for routine work with no expected quality regression.

## User Story

As a developer running SDLC workflows via `orchestrating-workflows`, I want the orchestrator to select an appropriately-sized model for each forked subagent based on the work item's complexity and the step's inherent demands, so that trivial chores and low-severity bugs don't burn Opus tokens on mechanical work while complex features still get the reasoning power they need.

## Motivation

Today every fork inherits the parent conversation's model via the Agent tool's default. When the user is on Opus 4.6, **every fork is Opus 4.6**, regardless of whether the work item is a two-line type annotation fix or a four-phase OAuth implementation.

**Concrete case** — BUG-001 in `lwndev/lwndev-site` was a pure-syntactic fix replacing two `querySelector<HTMLElement>(...)` generic-call sites with `querySelector(...) as HTMLElement | null`. The bug chain executed `reviewing-requirements ×2`, `executing-bug-fixes`, and `finalizing-workflow` — all on Opus — for a +2/-2 line diff. Every one of those forks could have run on Sonnet (validation and edit work) or Haiku (finalize). Rough estimate: ~4–6× the tokens for the fork work compared to an adaptive policy, for no quality benefit.

The Agent tool already accepts an optional `model` parameter (`opus`/`sonnet`/`haiku`) that overrides inheritance — but the orchestrator's fork call sites do not pass it, and there is no mechanism to classify work items.

## Design: Two-Axis Classification

Model selection per fork is computed as:

```
final_tier = max(step_baseline, work_item_complexity, overrides)
```

where `haiku < sonnet < opus`. This prevents:
- **Under-provisioning**: a simple bug cannot push `implementing-plan-phases` below its Sonnet baseline
- **Over-provisioning**: a low-severity bug cannot drag `finalizing-workflow` up to Opus

### Axis 1: Step Baselines

| Step | Baseline tier | Rationale |
|------|---------------|-----------|
| `reviewing-requirements` (any mode) | `sonnet` | Structured validation, bidirectional cross-reference, grep-heavy. Haiku risks missing subtle consistency errors. |
| `creating-implementation-plans` | `sonnet` | Most plans benefit from Sonnet; complex features get bumped via work-item signals. |
| `implementing-plan-phases` | `sonnet` | Per-phase fork. Heavy edits but typically scoped. Complex phases bump to Opus. |
| `executing-chores` | `sonnet` | Routine refactors, dependency bumps, cleanups. |
| `executing-bug-fixes` | `sonnet` | Root-cause-driven edit + test + PR. |
| `finalizing-workflow` | `haiku` | Mechanical: merge PR, checkout main, fetch, pull. **Baseline-locked** (see Exceptions). |
| PR creation (orchestrator inline fork) | `haiku` | Pure `gh pr create` with a templated body. **Baseline-locked**. |

Steps that run in **main context** — `documenting-*`, `documenting-qa`, `executing-qa` — are unaffected by this proposal; they run on whatever model the parent conversation uses.

### Axis 2: Work-Item Complexity Signals

Computed at workflow init from the requirement document and persisted to state.

| Chain | Signal | Stage | Value → tier |
|-------|--------|-------|-------------|
| **Chore** | Acceptance criteria count | init | ≤3 → `low`; 4–8 → `medium`; 9+ → `high` |
| **Bug** | Severity field | init | `low` → `low`; `medium` → `medium`; `high`/`critical` → `high` |
| **Bug** | Root-cause count (RC-N) | init | 1 → `low`; 2–3 → `medium`; 4+ → `high` |
| **Bug** | Category | init | `security` / `performance` → bump one tier; others → no change |
| **Feature** | FR count | init | ≤5 → `low`; 6–12 → `medium`; 13+ → `high` |
| **Feature** | NFR mentions security/auth/perf | init | yes → bump one tier |
| **Feature** | Phase count | post-plan | 1 → `low`; 2–3 → `medium`; 4+ → `high` *(applied after step 3; upgrade-only)* |

Work-item complexity = `max` of the applicable signals, then mapped: `low → haiku`, `medium → sonnet`, `high → opus`.

**Two-stage classification for features** — the feature phase count signal cannot be computed at workflow init because phases are produced by step 3 (`creating-implementation-plans`), not step 1. Feature classification therefore runs in two stages:

1. **Initial tier** (at workflow init, after step 1): computed from FR count and NFR signals only. Applied to forks in steps 2 and 3 (`reviewing-requirements` standard, `creating-implementation-plans`).
2. **Upgraded tier** (after step 3 completes): re-computed including phase count. Applied to all subsequent forks (test-plan reconciliation, phase loop, code-review reconciliation).

The upgraded tier is **upgrade-only** — if the phase count signal would produce a lower tier than the initial tier, the initial tier is retained. This prevents accidental downgrades when a simpler-than-expected plan is produced for a feature with many FRs.

**Chore and bug chains have no post-plan stage** — all their signals are available at init.

### Axis 3: Overrides (in precedence order)

1. **Skill argument** — `/orchestrating-workflows FEAT-001 --model opus`, `--complexity high`, or `--model-for <step>:<tier>`. Highest precedence, applies to the current invocation only.
2. **Workflow state override** — `modelOverride: opus|sonnet|haiku|null` field in `.sdlc/workflows/{ID}.json`. Editable by the user between `pause` and `resume` cycles via `workflow-state.sh set-complexity` (FR-15) or direct JSON edit.
3. **Computed tier** — lowest precedence; derived from step baseline and work-item complexity signals.

> **Note**: Requirement documents intentionally do **not** support YAML frontmatter fields for complexity or model override — see FR-5 for the rationale and docs-check that confirmed neither field exists in any Claude Code schema.

### Baseline-Locked Steps

`finalizing-workflow` and PR creation are **baseline-locked**: the work-item complexity bump does not apply to them. They always run at their baseline tier (`haiku`) unless an explicit override is given. Rationale: these are mechanical `gh` / `git` operations with no reasoning component, regardless of how complex the overall feature is.

## Functional Requirements

### FR-1: Step Baseline Mapping

The orchestrator SKILL.md defines a step baseline table documenting the minimum tier for each forked step. The table is the authoritative source and must match the mapping in Axis 1 above.

### FR-2: Work-Item Complexity Classification (Two-Stage for Features)

#### FR-2a: Initial Classification at Workflow Init

At workflow init (after step 1 documentation completes and the requirement artifact exists), the orchestrator reads the requirement document and computes `work_item_complexity` by:

1. Parsing the **init-stage** chain-specific signals listed in Axis 2 (skip post-plan signals)
2. Taking `max` of all applicable signals
3. Applying the `low/medium/high → haiku/sonnet/opus` mapping
4. Persisting the result to `.sdlc/workflows/{ID}.json` as `complexity` with `complexityStage: "init"`

For chore and bug chains, this is the only stage — all their signals are init-stage.

This runs once per workflow init. On resume, the orchestrator re-reads the document and compares (see FR-12 for caching behavior).

#### FR-2b: Post-Plan Upgrade for Features

After step 3 (`creating-implementation-plans`) completes in a feature chain, the orchestrator re-computes complexity including the **post-plan** Feature signals (phase count):

1. Parse phase count from the implementation plan at `requirements/implementation/{ID}-*.md`
2. Compute the phase-count tier using Axis 2's Feature "Phase count" row
3. Compute `upgraded_tier = max(persisted_complexity, phase_count_tier)` — **upgrade-only**; never downgrade
4. Update `complexity` and set `complexityStage: "post-plan"` in state

The upgraded tier applies to all feature-chain forks **from step 6 onward** (`reviewing-requirements` test-plan reconciliation is the first fork affected; step 5 is `documenting-qa` which runs in main context and is unaffected). It also applies to the phase loop, PR creation, post-PR code-review reconciliation, and `finalizing-workflow` (subject to baseline locks).

### FR-3: Final Tier Computation per Fork

Before every `Agent` tool fork call, the orchestrator resolves the final tier using explicit precedence logic (not a simple `max`). The algorithm walks a precedence chain, and the first non-null entry is applied using `replace` semantics for hard overrides and `max` semantics for soft overrides.

```
# Pseudocode — executed fresh for each fork call.
# Precedence order MUST mirror FR-5 exactly.
tier = step_baseline                                # 1. Start at baseline

# 2. Apply work-item complexity axis (unless baseline-locked)
if not step.baseline_locked:
    tier = max(tier, work_item_complexity)

# 3. Walk the override chain in FR-5 precedence order.
#    The FIRST non-null override wins — execution breaks out of the loop.
#    Hard overrides bypass the baseline lock and can downgrade the tier.
#    Soft overrides respect the baseline lock and are upgrade-only.
chain = [
    ("cli_model_for",   cli_model_for_flag.get(step.name),  "hard"),  # FR-5 #1
    ("cli_model",       cli_model_flag,                     "hard"),  # FR-5 #2
    ("cli_complexity",  cli_complexity_flag,                "soft"),  # FR-5 #3
    ("state_override",  state.modelOverride,                "soft"),  # FR-5 #4
]

for name, value, kind in chain:
    if value is None:
        continue
    if kind == "hard":
        # Hard override: replace tier entirely (even below baseline)
        tier = value
    else:
        # Soft override: upgrade-only, respects baseline lock
        if step.baseline_locked:
            # Soft overrides cannot push baseline-locked steps above baseline
            pass
        else:
            tier = max(tier, value)
    break  # first non-null wins

return tier
```

Key properties:

- **`--model-for <step>:<tier>` takes precedence over `--model <tier>`** because a more-specific per-step override should win over the blanket invocation override.
- **Hard overrides can downgrade below baseline** — `--model haiku` on a feature forces every fork to Haiku, including `reviewing-requirements` (baseline `sonnet`). This is intentional: explicit user instructions win, but the orchestrator logs a warning (Edge Case #11).
- **Soft overrides are strictly upgrade-only** — `--complexity low` on a computed `opus` tier has no effect because `max(opus, low)` = `opus`. This prevents accidental downgrades.
- **Baseline-locked steps ignore soft overrides** — `finalizing-workflow` stays on `haiku` regardless of `--complexity high`, but obeys `--model opus`.

The resolved tier is passed as the `model` parameter to the Agent tool call and recorded in `modelSelections`.

### FR-4: Baseline-Locked Steps

`finalizing-workflow` and the inline PR-creation fork are **baseline-locked**: the work-item complexity axis does not apply to them (FR-3 step 2 is skipped), and **soft overrides** (`--complexity`, state `modelOverride`) also respect the baseline lock — they can only upgrade non-baseline-locked steps.

**Hard overrides** — the `--model <tier>` and `--model-for <step>:<tier>` CLI flags — bypass the baseline lock and apply to all forks including `finalizing-workflow` and PR creation. This is the escape hatch for users who explicitly want to force every fork (or a specific step) to a specific tier.

A high-complexity feature with no overrides leaves `finalizing-workflow` and PR creation on `haiku`. A `--model opus` invocation forces them to `opus`.

### FR-5: Override Precedence

The orchestrator walks the override chain in this order (highest precedence first). The first non-null entry wins — precedence, not `max`.

1. **Hard — CLI `--model-for <step>:<tier>`** — applies only to the matching step. Replaces tier entirely. Bypasses baseline lock for that step.
2. **Hard — CLI `--model <tier>`** — applies to all forks including baseline-locked steps. Replaces tier entirely (can downgrade below baseline).
3. **Soft — CLI `--complexity <tier>`** — applied to the work-item complexity axis via `max(current, override)` (upgrade-only). Subject to baseline floor and baseline lock.
4. **Soft — Workflow state `modelOverride: <tier>`** — upgrade-only; respects baseline lock. Editable between pause and resume via `workflow-state.sh set-complexity` (FR-15) or direct JSON edit.
5. **Computed tier** — lowest precedence; derived from step baseline and work-item complexity signals.

**Why no requirement-doc frontmatter override?** Two independent checks confirmed that `complexity` and `model-override` are not recognized frontmatter fields anywhere in Claude Code's schemas:

1. **Local check** — `requirements/features/FEAT-012`, `FEAT-013`, `requirements/bugs/BUG-008`, and the `documenting-features` template at `plugins/lwndev-sdlc/skills/documenting-features/assets/feature-requirements.md` all start directly with the `# Feature Requirements: ...` heading — no YAML frontmatter block.
2. **Claude Code docs check** (via the `claude-code-guide` agent against code.claude.com) —
   - **Subagent frontmatter** valid fields: `name`, `description`, `prompt`, `model`, `effort`, `maxTurns`, `tools`, `disallowedTools`, `memory`, `background`, `isolation`, `color`, `initialPrompt`, `mcpServers`, `skills`, `hooks`, `permissionMode`. Neither `complexity` nor `model-override` appears.
   - **Skill frontmatter** valid fields: `name`, `description`, `argument-hint`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `model`, `effort`, `context`, `agent`, `hooks`, `paths`, `shell`. Neither `complexity` nor `model-override` appears.
   - **Plugin manifest** (`.claude-plugin/plugin.json`) has no such fields either.

Introducing `complexity: <tier>` or `model-override: <tier>` as new requirement-document frontmatter would:

- Create a new authoring convention for three documenting skills (feature, chore, bug) with no precedent
- Use field names that **collide in intent but not in schema** with Claude Code's real `model` field (subagent/skill frontmatter, accepting `sonnet`/`opus`/`haiku`/full-ID/`inherit`) and the real `effort` field (skill/subagent frontmatter, accepting `low`/`medium`/`high`/`max` for computational effort within a single invocation)
- Invite confusion with `effort` in particular — even though `effort` addresses a **different** layer (thinking budget within a model invocation, not which model is selected), a reader seeing `complexity: high` in a requirement doc could reasonably assume it maps to `effort` behavior
- Add a parser to the orchestrator for a single-use field set

Document-level override is instead expressed via `workflow-state.sh set-complexity` (run once after init) or CLI argument (`--model`, `--complexity`, `--model-for`). If per-document override becomes necessary in the future, an in-body section (like the existing `## GitHub Issue` pattern) is more consistent with the current "plain markdown" convention — see Future Enhancements.

> **Note on Claude Code `effort`**: The `effort: low|medium|high|max` field exists in Claude Code's subagent and skill frontmatter and controls computational effort within a model invocation (thinking/reasoning budget). It is **distinct** from model selection and is not used by this feature. A future enhancement could pass `effort` through to forked subagents as a separate axis (e.g., run `implementing-plan-phases` on `opus` with `effort: high` for genuinely hard phases), but that is out of scope here. FEAT-014 selects **which model** to use; `effort` controls **how hard that model thinks**.

### FR-6: *(removed — see FR-5 rationale)*

FR-6 previously proposed YAML front-matter fields `complexity` and `model-override` on requirement documents. This requirement has been removed because:

- Requirement documents in this repo have no existing YAML frontmatter convention
- Neither `complexity` nor `model-override` is a valid field in any Claude Code frontmatter schema (subagents, skills, plugin manifests)
- Subagent frontmatter uses a field called `model` (not `model-override`), so the proposed name would be misleading

Document-level override, if needed, is available via CLI argument (`--model`, `--complexity`, `--model-for`) or state file (`modelOverride`).

### FR-7: Workflow State File Extensions

The `.sdlc/workflows/{ID}.json` state schema gains four new fields:

```json
{
  "complexity": "low|medium|high",
  "complexityStage": "init|post-plan",
  "modelOverride": null,
  "modelSelections": [
    {
      "stepIndex": 2,
      "skill": "reviewing-requirements",
      "mode": "standard",
      "phase": null,
      "tier": "sonnet",
      "complexityStage": "init",
      "startedAt": "2026-04-11T15:30:00Z"
    },
    {
      "stepIndex": 7,
      "skill": "implementing-plan-phases",
      "mode": null,
      "phase": 1,
      "tier": "opus",
      "complexityStage": "post-plan",
      "startedAt": "2026-04-11T16:00:00Z"
    },
    {
      "stepIndex": 11,
      "skill": "finalizing-workflow",
      "mode": null,
      "phase": null,
      "tier": "haiku",
      "complexityStage": "post-plan",
      "startedAt": "2026-04-11T17:30:00Z"
    }
  ]
}
```

Field semantics:

- `complexity` — the computed work-item complexity tier (persisted at init, upgraded post-plan for features)
- `complexityStage` — `"init"` before feature step 3 completes, `"post-plan"` after (always `"init"` for chore/bug chains)
- `modelOverride` — user-editable override that applies to the whole workflow (null by default)
- `modelSelections` — audit trail as an **array** of entries (not a flat object), one per fork invocation. Written as each fork begins. Using an array (rather than a keyed object) is required because:
  - `reviewing-requirements` runs at up to 3 distinct steps per chain (standard, test-plan, code-review) — a flat object keyed by skill name would overwrite earlier entries
  - `implementing-plan-phases` runs N times per feature (once per phase) — requires per-phase rows
  - Fork retries (FR-11) produce multiple entries for the same step — array preserves history

Each entry records `stepIndex` (from the state file's `steps` array), `skill`, optional `mode` (for reviewing-requirements), optional `phase` (for implementing-plan-phases), resolved `tier`, `complexityStage` at the time of the fork (so init-stage vs post-plan forks are distinguishable in the audit trail), and `startedAt`.

### FR-8: Skill Argument Support

The orchestrator accepts two new optional flags alongside the existing ID argument:

```
/orchestrating-workflows FEAT-001 --model opus
/orchestrating-workflows FEAT-001 --complexity high
/orchestrating-workflows FEAT-001 --model-for implementing-plan-phases:opus
```

- `--model <tier>` — force all forks in this invocation to the given tier
- `--complexity <tier>` — force the work-item complexity axis to the given tier (baselines and overrides still apply)
- `--model-for <step>:<tier>` — optional; force a specific step to a specific tier (e.g., only upgrade `implementing-plan-phases`)

The existing argument parsing (ID, `#N`, free-text title) must continue to work; model flags are additive.

### FR-9: Pass Explicit Model on Every Fork

Every Agent tool fork call in the orchestrator SKILL.md is updated to pass an explicit `model` parameter. The value comes from the resolved tier computed by FR-3. No fork may inherit the parent model silently. This applies to:

- `reviewing-requirements` (standard, test-plan, code-review modes)
- `creating-implementation-plans`
- `implementing-plan-phases` (each phase)
- `executing-chores`
- `executing-bug-fixes`
- `finalizing-workflow`
- PR creation (inline orchestrator fork)

### FR-10: Fallback and Degradation

- **Unparseable signals**: If classification cannot compute a tier (malformed doc, missing signals), fall back to `sonnet` as the work-item complexity axis. **Never fall back to `opus`** — that would silently reintroduce over-provisioning.
- **No auto-downgrade below baseline**: Step baselines are a floor. Even if the work-item complexity says `haiku`, `reviewing-requirements` will still run on `sonnet`.
- **Parent-model floor is not applied by default**: Users who want the old inherit-parent behavior can pass `--model opus` explicitly (documented in the reference doc).

### FR-11: Fork Failure Retry with Tier Upgrade

If a fork errors or returns an empty artifact (classified by the orchestrator as "possibly under-provisioned"), the orchestrator retries **once** at the next tier up:

- `haiku` fork fails → retry on `sonnet`
- `sonnet` fork fails → retry on `opus`
- `opus` fork fails → record `fail` state, no further retry

The retry is only triggered for classifier-flagged failures (empty artifact, tool-use loop limit), not for every error (e.g., user-authored findings from `reviewing-requirements`). Normal findings-based pauses do not trigger tier upgrades.

### FR-12: Stage-Aware Re-computation on Resume

When the user re-invokes `/orchestrating-workflows {ID}` to resume, the orchestrator re-computes the work-item complexity and compares it to the persisted `complexity` field. Re-computation is **stage-aware and upgrade-only** to mirror FR-2b's safety guarantees:

1. **Determine current stage** from the persisted `complexityStage`:
   - If `"init"` → re-compute init-stage signals only (FR count, NFR mentions for features; severity/RC/category for bugs; acceptance criteria count for chores). Do not consult the implementation plan.
   - If `"post-plan"` → re-compute init-stage signals **and** read phase count from `requirements/implementation/{ID}-*.md`. Apply FR-2b's upgrade-only rule.
2. **Compute upgrade-only tier**: `new_tier = max(persisted_complexity, newly_computed_tier)`. The re-computation can only upgrade the tier, never downgrade — this prevents a user who soft-edited NFR wording between pause/resume from silently dropping `reviewing-requirements` below its intended tier.
3. **If the tier changed** (upgraded): log a one-line info message — `"[model] Work-item complexity upgraded since last invocation: <old> → <new>. Audit trail continues."` — update the persisted `complexity` field, and proceed with the new tier.
4. **If the tier is unchanged** (either unchanged or would have been a downgrade): proceed silently with the persisted tier.
5. **`complexityStage` transitions on resume**: `complexityStage` is never *reset* on resume. It only advances from `"init"` → `"post-plan"` when step 3 (`creating-implementation-plans`) completes for feature chains. Chore and bug chains stay at `"init"` for the entire workflow lifetime.

**Escape hatch for downgrades**: If a user genuinely wants to downgrade (e.g., they edited the doc to remove phases and want the phase count signal to retarget the tier), they can explicitly run `workflow-state.sh set-complexity {ID} <lower-tier>` between pause and resume. This is an explicit user action, not a silent side-effect of doc edits.

This handles cases where the user edited the requirement doc or implementation plan between `pause` and `resume`.

### FR-13: Backward Compatibility

Workflows initialized before this change (existing `.sdlc/workflows/{ID}.json` state files without the new fields) must continue to run:

- Missing `complexity` field → compute on resume
- Missing `modelOverride` field → treat as `null`
- Missing `modelSelections` field → start fresh audit trail
- Forks with no resolved tier → fall back to parent-model inheritance with a one-line info message per fork (the only situation where parent-model inheritance is allowed after this change)

### FR-14: Resolved Tier Console Echo

As each fork begins, the orchestrator prints a one-line message to the console showing the resolved tier and its derivation. Format:

```
[model] step 7 (implementing-plan-phases, phase 1) → opus (baseline=sonnet, wi-complexity=opus, override=none)
[model] step 11 (finalizing-workflow) → haiku (baseline=haiku, baseline-locked)
[model] step 2 (reviewing-requirements, standard) → opus (baseline=sonnet, wi-complexity=sonnet, override=--model opus)
```

This makes tier resolution visible during workflow execution without requiring operators to inspect `.sdlc/workflows/{ID}.json`. The same information is also persisted to `modelSelections` for post-mortem debugging.

### FR-15: `workflow-state.sh` Helpers

Two new subcommands for the state script:

```bash
# Override complexity for the workflow (sets modelOverride or complexity)
workflow-state.sh set-complexity {ID} {low|medium|high}

# Debug helper: return the resolved tier for a given step
workflow-state.sh get-model {ID} {step-name}
```

`get-model` computes the same `max(baseline, complexity, override)` as FR-3 and prints the result, enabling dry-run inspection without actually forking.

## Non-Functional Requirements

### NFR-1: Documentation Quality

The SKILL.md must contain a new **"Model Selection"** section between "Step Execution" and "Error Handling" with:

- The step baseline matrix (Axis 1)
- The work-item complexity signal matrix (Axis 2)
- Override precedence documentation (Axis 3)
- Baseline-locked step exceptions
- Worked examples for all three chain types at low/medium/high complexity (see Worked Examples below)

### NFR-2: Reference Documentation

A new `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` explains:

- The classification algorithm in detail with pseudocode
- How to tune per-step baselines if empirical quality differs from theory
- How to read the `modelSelections` audit trail
- Known limitations (e.g., "Haiku may struggle with `implementing-plan-phases` even on trivial features — we do not drop below Sonnet for that step regardless of signals")
- Migration guidance for users who want the old "inherit-parent-model" behavior (`--model opus` on every invocation, or a wrapper command)

### NFR-3: Quality Regression Debugging

The `modelSelections` audit trail must be written **as each fork begins**, not batched at workflow completion. This ensures that if a workflow crashes mid-fork, the state file still reflects which model was chosen for the failing step.

### NFR-4: No Silent Over-Provisioning

No step may be forked on Opus by default. Opus must come from one of:

- `high` work-item complexity (computed from signals)
- Explicit `--model opus` or `--model-for <step>:opus` CLI argument
- Explicit `modelOverride: opus` in the workflow state file

A fresh default invocation on a typical chore or low-severity bug must produce **zero** Opus fork calls.

### NFR-5: Error Handling

- Missing init-stage signals (e.g., requirement doc has no parseable FR/NFR/AC/severity): fall back to `sonnet`, not `opus` (FR-10)
- Missing post-plan signals (feature implementation plan not yet created when post-plan recomputation is triggered): retain the init-stage tier, log a warning, do not upgrade
- Invalid tier value in argument or state (`--model foo`): log error, abort with clear message
- Invalid `--model-for` step name (`--model-for nonexistent-skill:opus`): log warning, ignore the flag for that step, proceed with remaining overrides
- Unknown tier value rejected by Agent tool (Claude Code version predates per-invocation `model` support): see NFR-6

### NFR-6: Agent Tool `model` Parameter Compatibility

The per-invocation `model` parameter on the Agent tool was restored in Claude Code **2.1.72** (see `docs/shared/docs/anthropic/docs/en/changelog.md:129` — *"Restored the `model` parameter on the Agent tool for per-invocation model overrides"*, March 10, 2026). Tier values must be passed verbatim as aliases (`sonnet`, `opus`, `haiku`) — not full model IDs — because aliases are version-stable whereas model IDs change with every release.

- **Minimum Claude Code version**: 2.1.72 (enforced via version check in the orchestrator init path; log a warning and continue on older versions)
- **Alias form is authoritative**: The orchestrator always passes `sonnet`/`opus`/`haiku` as the `model` parameter, never a full model ID like `claude-opus-4-6`. This means the `[1m]` long-context variant cannot be selected via this mechanism — `opus` always resolves to whatever the standard Opus alias points to on the current Claude Code version
- **Fallback for older Claude Code**: If the Agent tool rejects the `model` parameter (tool-call error indicating unknown parameter), the orchestrator logs a one-line warning (`"[model] Agent tool rejected model parameter — falling back to parent-model inheritance for this fork. Upgrade to Claude Code 2.1.72+ for adaptive selection."`) and retries the fork once without the `model` parameter. This is the **only** situation after this change where parent-model inheritance is allowed

### NFR-7: Audit Trail Visibility

Both the console echo (FR-14) and the `modelSelections` array (FR-7) must be present for every fork. Operators debugging "why did this run on opus?" should be able to answer from either source without reading orchestrator source code.

## Dependencies

- **Claude Code ≥ 2.1.72** — Agent tool must support the per-invocation `model` parameter (see NFR-6 and `docs/shared/docs/anthropic/docs/en/changelog.md:129`). Older versions degrade gracefully via the NFR-6 fallback path.
- **Agent tool `model` parameter** — accepts aliases (`sonnet`/`opus`/`haiku`) or `inherit`; see `docs/shared/docs/anthropic/docs/en/sub-agents.md:219,234`
- Existing `orchestrating-workflows` skill and its `workflow-state.sh` script (fork call sites at `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:320`, `:327`, `:421`, `:464`, `:532` — all to be mutated to pass explicit `model`)
- Existing requirement document templates (feature, chore, bug) — **unchanged**; no frontmatter is added (see FR-5 rationale)
- A new `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/` directory (does not exist yet — must be created by the implementation plan alongside `model-selection.md`)

## Edge Cases

1. **State `modelOverride` conflicts with computed signals**: The state override wins per FR-5 (walk precedence chain, first non-null wins). Log both values at info level on the first fork to aid debugging.
2. **`--model-for` targets a step not in the current chain**: Log warning, ignore the flag for that step, proceed with remaining overrides.
3. **Skill argument overrides a baseline-locked step**: `--model opus` forces `finalizing-workflow` to Opus (hard overrides always win, even for baseline-locked steps). `--complexity high` does **not** — it's a soft override.
4. **Resume after manual state edit**: User edited `modelOverride` directly in the JSON file between pause/resume. The new value takes effect on resume (per FR-5 precedence chain).
5. **Empty requirement doc**: No signals to classify from. Fall back to `sonnet` work-item complexity (per FR-10).
6. **Workflow initialized before this change**: No `complexity` field in state. Compute on resume (per FR-13), then persist.
7. **Multiple fork retries in one workflow**: Each fork's retry budget is independent. One failing phase doesn't reduce the retry budget for subsequent phases.
8. **`implementing-plan-phases` per-phase classification**: Not supported in this iteration. All phases in a feature use the same tier (feature-level complexity). Per-phase classification is deferred (see Future Enhancements).
9. **Orchestrator invoked from a cron-scheduled agent or autonomous loop**: The parent conversation may itself be running on a lower tier than Opus (e.g., a cron agent started on Haiku for cost reasons). Because the orchestrator never "floors on parent" by default (FR-10), classification re-runs from signals on every invocation — the scheduled agent's model is irrelevant to fork tier selection. The pre-change backward-compat fallback in FR-13 (which uses parent-model inheritance) is a one-shot migration aid, not a steady-state behavior; it only triggers when the state file was created before this feature landed and has no `complexity` field. After one `compute on resume` cycle, subsequent invocations use computed tiers regardless of parent model.
10. **Feature chain initial tier differs from post-plan tier**: If FR count + NFR signals alone give `sonnet` but phase count pushes to `opus`, steps 2 and 3 run on Sonnet and steps 6 onward run on Opus (step 5 is `documenting-qa` in main context — unaffected). The audit trail captures the transition via per-entry `complexityStage` in `modelSelections`.
11. **Hard override that downgrades below baseline**: User passes `--model haiku` for a feature chain. `reviewing-requirements` has a Sonnet baseline. The hard override *replaces* the tier (per FR-3), so the fork runs on Haiku. This is allowed because hard overrides are explicitly user-authorized, but the orchestrator should log a one-line warning (`"[model] Hard override --model haiku bypassed baseline sonnet for reviewing-requirements. Proceeding at user request."`).

## Worked Examples

### Example A — Low-complexity chore

Chore: "Move `src/utils/example.test.ts` to `test/utils/example.test.ts` and drop `src/**` glob from `vitest.config.ts`."

- Acceptance criteria count: 5 → `medium`
- Work-item complexity: `medium` → `sonnet`

*(Chore chains use only the acceptance criteria count signal; "affected files count" is not used because chore templates do not enforce a parseable file-list schema.)*

| Step | Baseline | Final |
|------|----------|-------|
| `reviewing-requirements` (standard) | sonnet | sonnet |
| `reviewing-requirements` (test-plan) | sonnet | sonnet |
| `executing-chores` | sonnet | sonnet |
| `reviewing-requirements` (code-review) | sonnet | sonnet |
| `finalizing-workflow` | haiku | **haiku** *(baseline-locked)* |

Result: **zero Opus invocations**. Entire chain runs on Sonnet + Haiku.

### Example B — Low-severity bug (BUG-001 pattern)

Bug: the `querySelector<HTMLElement>` → `as HTMLElement | null` fix.

- Severity: `low` → `low`
- RC count: 1 → `low`
- Category: `logic-error` → no bump
- Work-item complexity: `low` → `haiku`

| Step | Baseline | Final |
|------|----------|-------|
| `reviewing-requirements` (standard) | sonnet | sonnet *(baseline floor)* |
| `reviewing-requirements` (test-plan) | sonnet | sonnet *(baseline floor)* |
| `executing-bug-fixes` | sonnet | sonnet *(baseline floor)* |
| `reviewing-requirements` (code-review) | sonnet | sonnet *(baseline floor)* |
| `finalizing-workflow` | haiku | haiku |

Result: again **zero Opus invocations** — step baselines floor minor-bug work at Sonnet, which is the right choice for validation/edit work even when the bug is trivial.

### Example C — Two-stage feature, init `sonnet` upgraded to `opus`

Feature: "Add a paginated search endpoint with cursor-based pagination" — 5 FRs, NFR section covers rate limiting and response latency (no security/auth mention). Implementation plan (produced by step 3) defines 4 phases because the change spans API, cache layer, index migration, and client SDK updates.

**Stage 1 — init classification** (after step 1, before step 3):

- FR count: 5 → `low`
- NFRs mention security/auth/perf: "rate limiting" and "latency" → perf match → bump by one tier → `medium`
- **Initial** work-item complexity: `medium` → `sonnet`
- *(Phase count signal not yet available — plan not created)*

**Stage 2 — post-plan classification** (after step 3):

- Phase count: 4 → `high`
- `max(persisted_sonnet, phase_count_opus)` = `opus` — **upgrade** triggered
- **Upgraded** work-item complexity: `high` → `opus`

The audit trail will show two transitions: steps 2 and 3 resolved at `complexityStage: "init"` with `tier: "sonnet"`, and steps 6 onward resolved at `complexityStage: "post-plan"` with `tier: "opus"`.

| Step | Baseline | Final | Stage |
|------|----------|-------|-------|
| 2. `reviewing-requirements` (standard) | sonnet | **sonnet** | init |
| 3. `creating-implementation-plans` | sonnet | **sonnet** | init |
| 5. `documenting-qa` (main) | — | parent's model | — |
| 6. `reviewing-requirements` (test-plan) | sonnet | **opus** | post-plan |
| 7–10. `implementing-plan-phases` × 4 | sonnet | **opus** | post-plan |
| 11. PR creation | haiku | **haiku** *(baseline-locked)* | — |
| 13. `reviewing-requirements` (code-review) | sonnet | **opus** | post-plan |
| 15. `finalizing-workflow` | haiku | **haiku** *(baseline-locked)* | — |

Result: the review and planning work happens on Sonnet (fine for a 5-FR scope with performance NFRs), but once the 4-phase implementation plan materializes, everything downstream upgrades to Opus for the phase execution and reconciliation. `finalizing-workflow` and PR creation remain on `haiku` because the work-item complexity axis does not apply to baseline-locked steps (FR-4) — only a hard `--model` override could push them up.

### Example D — High-complexity feature where both stages resolve to Opus

Feature: "Add OAuth2 login with PKCE" — 12 FRs, NFR section covers session token storage and replay protection (security mention). Plan defines 4 phases.

- Init stage: 12 FRs → `medium`, security NFR bumps → `high` → `opus`
- Post-plan stage: 4 phases → `high`, `max(opus, opus)` = `opus`, no transition visible

For this feature every fork above baseline runs on Opus from step 2 onward. This is the steady-state case for genuinely high-complexity features where the init-stage signals alone are already decisive — the post-plan recomputation is a no-op.

### Self-classification sanity check

FEAT-014 itself classifies as high-complexity under its own rules: 14 FRs (FR-1 through FR-15, minus the now-removed FR-6 — bucket: 13+ → `high`), NFR-6 addresses compatibility rather than security/auth/perf so no bump. Initial feature classification: `high` → `opus`. Phases unknown until step 3 completes. This is a useful sanity check that the FR count thresholds are sensible — a feature substantial enough to warrant this detailed a requirements doc *should* classify as high-complexity.

## Relationship to Other Issues

- **#119 / FEAT-012 `managing-work-items`** — independent; work-items skill is already extracted. Model selection is a separate orchestration concern.
- **#120 `managing-source-control`** — independent; source-control skill could itself be classified as `haiku` baseline since git/PR ops are mechanical.
- **#129 `reconciling-drift`** — when that skill lands, it should participate in the same classification scheme. Drift reconciliation is probably `sonnet` baseline with a `medium` default.
- **`qa-verifier` subagent (Sonnet)** — already hardcoded to Sonnet via its agent definition. This proposal does not change that; it only affects forks dispatched from the orchestrator via the Agent tool.

## Testing Requirements

### Unit / Component Tests

- Override chain walk in FR-3 pseudocode order returns the correct value at each precedence level
- Signal extractors correctly derive tiers from synthetic requirement docs (chore, bug, feature)
- `max` tier computation returns the higher of two tiers across all 9 combinations
- Override precedence chain returns the correct value at each level
- Baseline-locked steps ignore work-item complexity bumps
- Invalid tier values (`foo`) produce clear error messages

### Integration Tests

- Synthetic chore workflow with `severity: low`, 2 affected files → zero Opus forks
- Synthetic bug chain (low severity, 1 RC) → zero Opus forks
- Synthetic feature with 4 phases and security NFR → Opus forks for review/plan/phase steps, Haiku for finalize
- `--model opus` override → all forks (including baseline-locked) run on Opus
- Resume from pre-existing state file without `complexity` field → classification runs and persists
- Fork failure retry path: mock a failing Haiku fork → orchestrator retries on Sonnet
- Fork failure retry exhaustion: mock failing Opus fork → orchestrator records `fail`

### Manual Testing

- Run a real chore workflow on this repo and verify `modelSelections` audit trail
- Run a real bug chain with `severity: low` and verify no Opus forks
- Edit `modelOverride` in state file between pause and resume, verify new value takes effect
- Run `workflow-state.sh set-complexity CHORE-NNN high` between pause and resume and verify all subsequent forks upgrade

## Future Enhancements

- **Per-phase classification for `implementing-plan-phases`**: Classify each phase independently based on phase-level signals (e.g., "Phase 1 is a data model change" → Opus, "Phase 2 is adding CSS" → Sonnet). Requires implementation plan to expose per-phase signals.
- **Quality measurement harness**: Benchmark suite to verify lower-tier models aren't silently producing worse results.
- **Long-context variant selection**: The `claude-opus-4-6[1m]` variant exists. Separate knob for context-window selection (not tier selection).
- **Wrapper for "always Opus" behavior**: If enough users want the old inherit-parent behavior, add a convenience wrapper command.
- **Parent-model floor as opt-in**: `--floor-on-parent` flag that uses the parent conversation's model as the minimum tier.

## Acceptance Criteria

- [ ] `orchestrating-workflows/SKILL.md` contains a new "Model Selection" section with the step baseline matrix, complexity signal matrix, and override precedence documentation (NFR-1)
- [ ] `orchestrating-workflows/references/model-selection.md` exists with the full classification algorithm and worked examples (NFR-2). The parent `references/` directory is created as part of this change
- [ ] Orchestrator computes **initial** work-item complexity from init-stage requirement doc signals at workflow init and persists it to `.sdlc/workflows/{ID}.json` as `complexity` with `complexityStage: "init"` (FR-2a)
- [ ] Feature chains re-compute complexity after step 3 (`creating-implementation-plans`) including phase count; the upgraded tier is **upgrade-only** (never downgrades) and `complexityStage` is set to `"post-plan"` (FR-2b)
- [ ] Chore and bug chains use only init-stage signals — no post-plan stage (FR-2a)
- [ ] Chore classification uses only acceptance criteria count as the complexity signal; "affected files count" is **not** used (Axis 2, E2 fix)
- [ ] Orchestrator persists per-fork model selections to `.sdlc/workflows/{ID}.json` as `modelSelections`, an **array** of entries with `{stepIndex, skill, mode, phase, tier, startedAt}` (FR-7). Array format preserves history across repeated skill invocations, phase loops, and fork retries
- [ ] `modelSelections` entries are written **as each fork begins** (not batched at workflow completion), so crashes mid-fork leave an accurate audit trail (NFR-3)
- [ ] Orchestrator passes an explicit `model` parameter on every Agent tool fork call based on the FR-3 resolution algorithm (baseline → work-item complexity with baseline-locks → override chain with hard/soft distinction) (FR-9)
- [ ] Tier resolution is echoed to the console as each fork begins, in a one-line format showing the derivation (`baseline=`, `wi-complexity=`, `override=`) (FR-14)
- [ ] `finalizing-workflow` and PR creation baseline tier is `haiku` and is **baseline-locked** against the work-item complexity axis **and soft overrides** (FR-4). Only **hard** overrides (`--model`, `--model-for`) bypass the baseline lock
- [ ] `reviewing-requirements`, `creating-implementation-plans`, `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes` baseline tier is `sonnet` (FR-1, Axis 1)
- [ ] No step is forked on Opus by default — only by `high` work-item complexity or explicit override (NFR-4)
- [ ] Requirement documents retain their existing plain-markdown convention — **no** YAML frontmatter is added for complexity or model override (FR-6 removed; rationale documented in FR-5)
- [ ] Workflow state file supports `modelOverride` field (soft override) editable between pause and resume (FR-7)
- [ ] Skill argument supports `--model <tier>` (hard), `--complexity <tier>` (soft), and `--model-for <step>:<tier>` (hard, per-step) for per-invocation overrides (FR-8)
- [ ] Override precedence walks the chain in FR-5 order, with the first non-null entry winning (not `max` — precedence wins)
- [ ] Hard vs soft override distinction is enforced: soft overrides respect baseline locks; hard overrides bypass them
- [ ] Classification falls back to `sonnet` (not `opus`) when signals are unparseable or missing (FR-10)
- [ ] Classification never auto-downgrades below a step's baseline tier when using soft overrides or computed tiers (FR-10)
- [ ] `workflow-state.sh` supports a new `set-complexity <ID> <tier>` command for programmatic override (FR-15)
- [ ] `workflow-state.sh` supports a new `get-model <ID> <step-name>` debug helper that returns the resolved tier without forking (FR-15)
- [ ] Fork failure retry path: if a fork errors or returns an empty artifact, retry once at the next tier up (haiku → sonnet → opus), then `fail` the workflow (FR-11)
- [ ] Resume re-computes work-item complexity and logs if it changed since the last invocation (FR-12)
- [ ] Tier aliases (`sonnet`/`opus`/`haiku`) are passed verbatim to the Agent tool's `model` parameter — not full model IDs (NFR-6)
- [ ] Minimum Claude Code version enforced: 2.1.72+ for adaptive selection; older versions log a warning and fall back to parent-model inheritance (NFR-6)
- [ ] If the Agent tool rejects the `model` parameter (unknown-parameter error), the orchestrator retries the fork once without the parameter and logs a warning (NFR-6)
- [ ] Acceptance test: running a synthetic bug chain with `severity: low`, 1 RC produces zero Opus fork invocations
- [ ] Acceptance test: running a synthetic chore with 5 acceptance criteria and no overrides produces zero Opus fork invocations (all Sonnet + Haiku)
- [ ] Acceptance test: running a synthetic feature chain with 4 phases and an NFR mentioning "security" produces Opus fork invocations for all reviewing-requirements, creating-implementation-plans, and implementing-plan-phases calls — and produces Haiku for `finalizing-workflow` and PR creation (baseline-locked)
- [ ] Acceptance test: `--model opus` override forces all forks to Opus regardless of classification (including baseline-locked steps)
- [ ] Acceptance test: `--complexity high` forces work-item complexity to `high` but `finalizing-workflow` still runs on `haiku` (baseline-locked against soft overrides)
- [ ] Acceptance test: `--model haiku` on a feature chain downgrades `reviewing-requirements` below its Sonnet baseline (hard override wins) and logs a baseline-bypass warning
- [ ] Acceptance test: feature chain with few FRs but 4 phases produces Sonnet forks for steps 2–3 and Opus forks for steps 5+ (two-stage classification); audit trail shows the transition
- [ ] Acceptance test: orchestrator invoked from a cron-scheduled agent running on Haiku still classifies correctly from signals (does not floor on parent model)
- [ ] Backward compatibility: workflows initialized before this change (existing `.json` state files without the new fields) continue to run, defaulting to parent-model inheritance with a one-line info message per fork until complexity is computed on next resume (FR-13)
- [ ] All skills pass `npm run validate`
