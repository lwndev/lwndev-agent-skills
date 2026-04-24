# Model Selection Reference

This document is the canonical, tutorial-length reference for the adaptive
model selection algorithm used by the `orchestrating-workflows` skill
(FEAT-014). The in-SKILL "Model Selection" section in `SKILL.md` is a
concise summary; this file is where the full algorithm, tuning guidance,
audit-trail format, known limitations, and migration guidance live.

If you are only debugging a single fork decision, the summary in `SKILL.md`
plus the FR-14 console echo line is usually enough. Read this file when you
need to understand *why* a particular tier was chosen, tune per-step
baselines, read the persisted audit trail, or migrate away from the new
adaptive behavior.

## Table of Contents

1. [Why adaptive selection](#why-adaptive-selection)
2. [The two-axis design](#the-two-axis-design)
3. [FR-3 classification algorithm — full pseudocode](#fr-3-classification-algorithm--full-pseudocode)
4. [Hard vs soft override rules](#hard-vs-soft-override-rules)
5. [Signal extractors — full pseudocode](#signal-extractors--full-pseudocode)
6. [Tuning per-step baselines](#tuning-per-step-baselines)
7. [Reading the `modelSelections` audit trail](#reading-the-modelselections-audit-trail)
8. [Known limitations](#known-limitations)
9. [Migration guidance](#migration-guidance)
10. [Why requirement docs have no complexity/model-override frontmatter](#why-requirement-docs-have-no-complexitymodel-override-frontmatter)

## Why adaptive selection

Before FEAT-014, every Agent-tool fork in the orchestrator inherited the
parent conversation's model. When the parent was Opus, every fork was Opus —
including `finalizing-workflow` (whose entire job is `gh pr merge && git
checkout main && git pull`) and low-severity bug fix chains with two-line
diffs. The token cost was an order of magnitude higher than necessary for
routine work, with no quality benefit.

The adaptive policy classifies each work item by complexity signals in its
requirement document, maps that classification onto per-step baseline tiers,
and applies user overrides in a documented precedence chain. Mechanical
steps default to Haiku, most validation and execution steps default to
Sonnet, and only genuinely high-complexity features bump to Opus.

The goal is captured in NFR-4: **a fresh default invocation on a typical
chore or low-severity bug must produce zero Opus fork calls**. Opus is
reserved for complexity that is explicit in the requirement doc or that the
user requested with a CLI flag.

## The two-axis design

Model selection per fork is computed as a two-axis lookup combined with an
override chain:

```text
final_tier = walk_override_chain(
    base = max(step_baseline, work_item_complexity),
    overrides = [cli_model_for, cli_model, cli_complexity, state_model_override]
)
```

- **Axis 1 — Step baseline**: the minimum tier for a given step, set per
  step based on its inherent cognitive demands. `finalizing-workflow` and PR
  creation have a `haiku` baseline and are baseline-locked; all other
  forked steps have a `sonnet` baseline.
- **Axis 2 — Work-item complexity**: a `low|medium|high` label computed
  once at workflow init from the requirement document, optionally upgraded
  after the implementation plan is created (feature chains only). Maps to
  tiers via `low → haiku`, `medium → sonnet`, `high → opus`.
- **Axis 3 — Overrides**: CLI flags and state-file fields, walked in FR-5
  precedence order. Hard overrides replace the tier; soft overrides are
  upgrade-only.

Tiers are ordered `haiku < sonnet < opus`. The `max` tier helper returns
whichever of two tiers is higher in this ordering.

See `SKILL.md` "Model Selection" section for the step baseline matrix (Axis
1), the work-item complexity signal matrix (Axis 2), and the override
precedence table (Axis 3).

## FR-3 classification algorithm — full pseudocode

The orchestrator runs this algorithm fresh before every Agent-tool fork
call. The shell implementation lives in
`${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` as the `resolve-tier`
subcommand, and the pseudocode below is the canonical reference — the shell
implementation mirrors it verbatim.

```text
# Inputs:
#   step_name            — name of the step being forked
#                          (e.g. "reviewing-requirements")
#   cli_model            — --model flag from CLI (hard, blanket)
#   cli_complexity       — --complexity flag from CLI (soft, blanket)
#   cli_model_for        — --model-for flag from CLI (hard, per-step)
#   state_complexity     — persisted .complexity from state file
#                          (low/medium/high)
#   state_model_override — persisted .modelOverride from state file (soft)

baseline = step_baseline(step_name)         # Axis 1: sonnet or haiku
locked   = step_baseline_locked(step_name)  # true for finalizing-workflow
                                            # and pr-creation

# Step 1: start at baseline
tier = baseline

# Step 2: apply work-item complexity axis (skipped for baseline-locked steps)
if not locked:
    wi_tier = complexity_to_tier(state_complexity)
    # low → haiku, medium → sonnet, high → opus
    if wi_tier is not None:
        tier = max(tier, wi_tier)

# Step 3: walk the override chain in FR-5 precedence order.
# The FIRST non-null entry wins — break out of the loop on match.
chain = [
    (cli_model_for.get(step_name),  "hard"),  # FR-5 #1 per-step replace
    (cli_model,                     "hard"),  # FR-5 #2 blanket replace
    (cli_complexity,                "soft"),  # FR-5 #3 upgrade-only max
    (state_model_override,          "soft"),  # FR-5 #4 upgrade-only max
]

for (value, kind) in chain:
    if value is None:
        continue
    if kind == "hard":
        # Hard override: replace tier entirely. May downgrade below baseline.
        # May bypass baseline lock (finalizing-workflow on --model opus is
        # legal).
        tier = value
    else:
        # Soft override: upgrade-only. Respects baseline lock.
        if locked:
            pass  # baseline-locked steps reject soft overrides
        else:
            soft_tier = value
            if soft_tier is a complexity label (low/medium/high):
                soft_tier = complexity_to_tier(soft_tier)
            tier = max(tier, soft_tier)
    break  # first non-null wins

return tier
```

Key properties:

- **`--model-for <step>:<tier>` takes precedence over `--model <tier>`**
  because a more-specific per-step override should win over the blanket
  invocation override.
- **Hard overrides can downgrade below baseline** — `--model haiku` on a
  feature forces every fork to Haiku, including `reviewing-requirements`
  (baseline `sonnet`). This is intentional: explicit user instructions win,
  but the orchestrator logs a warning (Edge Case 11 in the requirement doc).
- **Soft overrides are strictly upgrade-only** — `--complexity low` on a
  computed `opus` tier has no effect because `max(opus, low)` = `opus`.
  This prevents accidental downgrades.
- **Baseline-locked steps ignore soft overrides** —
  `finalizing-workflow` stays on `haiku` regardless of `--complexity high`,
  but obeys `--model opus`.

The resolved tier is passed as the `model` parameter to the Agent tool call
and recorded in `modelSelections`.

### Live invocation via `prepare-fork.sh`

In production the orchestrator does not run the pseudocode above inline — it
invokes `${CLAUDE_PLUGIN_ROOT}/scripts/prepare-fork.sh` per fork (see
FEAT-021). The script composes the four-step pre-fork ceremony — SKILL.md
readability check, tier resolution via `workflow-state.sh resolve-tier`,
audit-trail write via `workflow-state.sh record-model-selection`, and the
FR-14 echo line — into a single call and prints the resolved tier on stdout
so the orchestrator can pass it verbatim as the Agent tool's `model`
parameter.

The pseudocode above remains the canonical reference for the
tier-resolution algorithm itself; `prepare-fork.sh` is its scripted
composer, not a replacement spec. Tune baselines, thresholds, and override
semantics by editing `workflow-state.sh` and its test suite — the script
just calls those subcommands in the documented order.

## Hard vs soft override rules

| Rule | Hard overrides (`--model`, `--model-for`) | Soft overrides (`--complexity`, `modelOverride`) |
|------|-------------------------------------------|-------------------------------------------------|
| Replace vs upgrade | Replace the tier entirely | `max(current, override)` — upgrade-only |
| Baseline lock | Bypass the lock (can push baseline-locked steps off their baseline) | Respect the lock (baseline-locked steps ignore soft overrides) |
| Can downgrade below baseline? | Yes, with a one-line warning (Edge Case 11) | No — never downgrades below baseline |
| Per-step vs blanket | Both forms supported (`--model-for` per-step beats `--model` blanket) | Blanket only |

Concrete examples:

- `--model haiku` on a default feature chain forces `reviewing-requirements`
  to `haiku`, even though the baseline is `sonnet`. Emit the Edge Case 11
  baseline-bypass warning.
- `--model opus` on any chain forces `finalizing-workflow` to `opus`, even
  though it is baseline-locked at `haiku`. Hard overrides bypass locks.
- `--complexity low` on a work item already classified `high` has no effect
  because `max(opus, haiku) = opus`. Soft overrides are strictly upgrade-only.
- `modelOverride: "opus"` in state on `finalizing-workflow` is ignored
  because `finalizing-workflow` is baseline-locked and soft overrides
  respect the lock.
- `--model-for reviewing-requirements:opus --model haiku` resolves to
  `opus` for `reviewing-requirements` (per-step hard beats blanket hard,
  FR-5 #1 > #2) and `haiku` for every other fork (blanket hard wins there).

## Signal extractors — full pseudocode

Parsing is strictly local: no network calls, no LLM invocations, just
markdown regex and section walking. The shell implementations live in
`${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` and the pseudocode below is
the canonical reference.

### Chore signal extractor

```text
read the requirement document at requirements/chores/{ID}-*.md
locate the `## Acceptance Criteria` heading
count list items matching `- [ ]` or `- [x]` until the next `## ` heading or EOF
→ ≤3 items       → low
→ 4–8 items      → medium
→ 9+ items       → high
→ heading absent → unparseable → FR-10 fallback → medium
```

Only the acceptance criteria count is used. Chore docs do not enforce a
parseable file-list schema, so "affected files count" is intentionally not
a signal.

### Bug signal extractor

```text
read the requirement document at requirements/bugs/{ID}-*.md

severity_tier:
  read the first non-empty line under `## Severity`, strip backticks, lowercase
  → "low"                → low
  → "medium"             → medium
  → "high" or "critical" → high
  → anything else        → unset

rc_count_tier:
  count numbered list items (`1.`, `2.`, …) under `## Root Cause(s)`
  if the heading is absent, fall back to counting distinct `RC-N` mentions in the whole doc
  → 1 item    → low
  → 2–3 items → medium
  → 4+ items  → high
  → 0 items   → unset

if severity_tier is unset and rc_count_tier is unset:
  → unparseable → FR-10 fallback → medium
else:
  base = max(severity_tier, rc_count_tier)   # unknown sides are ignored

category:
  read the first non-empty line under `## Category`, strip backticks, lowercase
  if category in {"security", "performance"}:
    base = bump_one_tier(base)                # low→medium, medium→high, high→high

return base
```

### Feature init-stage signal extractor (FR-2a)

```text
read the requirement document at requirements/features/{ID}-*.md

fr_count:
  locate the `## Functional Requirements` heading
  count `### FR-N:` sub-headings until the next `## ` heading or EOF
  SKIP any heading line whose text contains the literal "removed" (case-insensitive)
  → ≤5 items   → low
  → 6–12 items → medium
  → 13+ items  → high

nfr_bump:
  locate the `## Non-Functional Requirements` heading
  scan the section body (case-insensitive) for the substrings
    "security", "auth", "perf"
  → any match      → true
  → no match       → false
  → section absent → unset

if fr_count is unset and nfr_bump is unset:
  → unparseable → FR-10 fallback → medium

base = fr_count (or medium if fr_count is unset)
if nfr_bump == true:
  base = bump_one_tier(base)
return base
```

### Feature post-plan signal extractor (FR-2b)

This stage runs exactly once in a feature chain, after step 3
(`creating-implementation-plans`) completes and before any subsequent fork
resolves its tier. It is **upgrade-only**: it can never downgrade the tier
computed at init.

```text
read the implementation plan at requirements/implementation/{ID}-*.md
count `### Phase N:` headings
→ 1 phase                → low
→ 2–3 phases             → medium
→ 4+ phases              → high
→ plan absent or 0 phases → NFR-5: retain persisted init-stage tier,
                            log warning, do not upgrade

new_tier = max(persisted_complexity, phase_count_tier)   # upgrade-only
if new_tier != persisted_complexity:
  persist new_tier, set complexityStage = "post-plan", emit upgrade log
else:
  proceed silently with persisted tier
```

Chore and bug chains have no post-plan stage — all their signals are
init-stage.

### FR-10 unparseable-signal fallback

When a signal extractor cannot produce a value (missing section, zero
matches, empty document, missing file), the classifier falls back to the
complexity label `medium`, which maps to the `sonnet` tier. It **never**
falls back to `opus` — silently reintroducing over-provisioning is exactly
the behavior FEAT-014 exists to prevent.

## Tuning per-step baselines

Baselines live in a single hardcoded table inside
`${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` (look for
`_step_baseline`). If empirical quality on a given step diverges from
theory, adjust the baseline table there — the change automatically
propagates to every fork call site because they all go through
`resolve-tier`.

Guidance for tuning decisions:

- **Raising a baseline is usually safe** — it only increases the minimum
  tier for that step, which means more tokens but higher quality. Do this
  when you observe systematic quality regressions (hallucinated code,
  missed review issues, inconsistent refactors) on a specific step.
- **Lowering a baseline is risky** — Haiku is noticeably weaker than Sonnet
  at multi-file reasoning and subtle consistency checks. Before dropping
  `reviewing-requirements` or `creating-implementation-plans` to `haiku`,
  run a shadow comparison across a sample of real workflows and confirm
  the artifacts are indistinguishable.
- **Do not drop `implementing-plan-phases` below `sonnet`** — phases are
  the highest-risk fork in the chain (multi-file edits, test runs, commit
  boundaries). Even "trivial" phases routinely touch code paths where a
  wrong rename propagates silently.
- **`finalizing-workflow` should stay on `haiku`** — its entire job is
  `gh pr merge && git checkout main && git pull`. Upgrading it to Sonnet
  costs tokens with zero quality benefit. If you want to force it higher
  for a single run, use `--model opus` (hard override bypasses the
  baseline lock).
- **Work-item complexity thresholds are also tunable** — if chores with
  4–8 acceptance criteria consistently feel like `low` complexity in
  practice, adjust the bucket boundaries in the `_classify_chore`
  function. The same applies to bug severity, RC count, feature FR count,
  and feature phase count thresholds. Keep the buckets monotonic and
  document the new thresholds in this file.

Any baseline or threshold change should land as a separate small PR with
a brief empirical justification — do not batch tuning changes with
feature work.

## Reading the `modelSelections` audit trail

Every workflow state file at `.sdlc/workflows/{ID}.json` contains a
`modelSelections` array that records every fork invocation. Each entry is
written **before** the fork begins, so a crashed fork still leaves an
accurate record. Retries (FR-11) append additional entries rather than
overwriting earlier ones.

### Field reference

```json
{
  "stepIndex": 2,
  "skill": "reviewing-requirements",
  "mode": "standard",
  "phase": null,
  "tier": "sonnet",
  "complexityStage": "init",
  "startedAt": "2026-04-11T15:30:00Z"
}
```

- **`stepIndex`** — zero-based index into the state file's `steps` array.
  Matches the step order shown by `workflow-state.sh status`.
- **`skill`** — the forked skill's name. For inline forks not backed by a
  standalone skill (PR creation), this is `"pr-creation"`.
- **`mode`** — populated for `reviewing-requirements` only. The
  orchestrator writes one of `"standard"` or `"test-plan"`; `"code-review"`
  is a valid historical value that remains readable for backwards
  compatibility (pre-FEAT-017 state files and manual invocations of
  `/reviewing-requirements --pr` may still record it, but the orchestrator
  no longer writes it). `null` for every other skill.
- **`phase`** — populated for `implementing-plan-phases` only. One-based
  phase number (e.g. `1` for the first phase). `null` for every other
  skill.
- **`tier`** — the resolved tier that was passed as the Agent tool's
  `model` parameter. One of `"haiku"`, `"sonnet"`, `"opus"`.
- **`complexityStage`** — the workflow's `complexityStage` at the time
  this fork was resolved. `"init"` for early-stage forks in any chain, or
  `"post-plan"` for feature-chain forks after
  `creating-implementation-plans` completes. This field is how you tell
  an init-stage sonnet fork apart from a post-plan upgraded opus fork
  when scanning the audit trail.
- **`startedAt`** — ISO-8601 UTC timestamp of when the orchestrator
  resolved the tier and began the fork.

### Querying the audit trail

```bash
# Show every fork's resolved tier in order
jq -r '.modelSelections[] | "\(.stepIndex): \(.skill) \(.mode // "") \(.phase // "") → \(.tier) (\(.complexityStage))"' \
    .sdlc/workflows/FEAT-014.json

# Count fork invocations by tier
jq -r '.modelSelections[].tier' .sdlc/workflows/FEAT-014.json | sort | uniq -c

# Show only the post-plan upgraded forks for a feature chain
jq '.modelSelections[] | select(.complexityStage == "post-plan")' \
    .sdlc/workflows/FEAT-014.json

# Show every retry entry (multiple entries for the same stepIndex)
jq -r '.modelSelections | group_by(.stepIndex) | .[] | select(length > 1)' \
    .sdlc/workflows/FEAT-014.json
```

### Common debugging questions

- **"Why did this workflow run on Opus?"** — scan the audit trail for any
  `tier: "opus"` entry, then cross-reference its `complexityStage` and
  `skill`. If `complexityStage: "init"` and `skill: "reviewing-requirements"`,
  either the requirement doc triggered a `high` init classification or an
  override was applied — check the state file's `complexity` and
  `modelOverride` fields plus the FR-14 console echo that was emitted
  before the fork for the `override=` tag.
- **"Why didn't `finalizing-workflow` upgrade to Opus for this feature?"** —
  it is baseline-locked and ignores work-item complexity and soft
  overrides. The only paths that push it above `haiku` are `--model opus`
  or `--model-for finalizing-workflow:opus` on the invocation.
- **"Why are there two entries for the same stepIndex?"** — FR-11
  retry-with-tier-upgrade. The first entry is the failed attempt, the
  second is the retry at the next tier up. Both the `tier` field and the
  `startedAt` timestamp distinguish them.

## Known limitations

- **Haiku is never selected for `implementing-plan-phases` regardless of
  signals.** The Sonnet baseline floor enforces this even when work-item
  complexity is `low`. Per-phase classification is also not supported in
  this iteration — all phases of a single feature run on the same
  feature-level tier (Edge Case 8 in the requirement doc).
- **Alias form only — no full model IDs.** The orchestrator always passes
  `sonnet`, `opus`, or `haiku` to the Agent tool's `model` parameter,
  never a full model ID like `claude-opus-4-6-20250219`. This means the
  `[1m]` long-context Opus variant cannot be selected via FEAT-014 —
  `opus` resolves to whatever the standard Opus alias points to on the
  current Claude Code version. If you need the long-context variant,
  launch the parent conversation on it and use `--model opus` to force
  every fork to the same tier (they will still be standard Opus, not
  long-context — FEAT-014 is not a way around that).
- **Main-context steps are unaffected.** `documenting-*`, `documenting-qa`,
  and `executing-qa` run in the orchestrator's own conversation, not in a
  fork, and therefore use whatever model the parent runs on. If you are
  on Opus when you invoke `/orchestrating-workflows`, those steps run on
  Opus regardless of work-item complexity.
- **Signal parsing is regex-based and therefore template-sensitive.** If
  you significantly restructure a requirement document template (renaming
  the `## Acceptance Criteria` heading, changing the `### FR-N:` format,
  etc.), the signal extractors may fail and fall back to `sonnet` via the
  FR-10 path. This is a safety behavior, not a bug, but it means
  classification will be less accurate until you update the extractor to
  match the new template.
- **Claude Code version floor is 2.1.72.** Older versions do not support
  the Agent tool's per-invocation `model` parameter and will silently
  fall back to parent-model inheritance (with a one-line warning per
  fork) via the NFR-6 fallback. This is the only path in the post-change
  codebase where parent-model inheritance is allowed.

## Migration guidance

If you want to disable adaptive model selection and restore the old
"every fork runs on whatever the parent is" behavior:

### Option 1: `--model opus` on every invocation (per-invocation)

```bash
/orchestrating-workflows FEAT-001 --model opus
```

`--model` is a hard override that replaces the tier entirely for every
fork, including baseline-locked steps. This is the closest behavioral
match to the pre-FEAT-014 default on an Opus parent conversation.

### Option 2: Shell wrapper alias (persistent)

Add the following to your shell rc file so every `/orchestrating-workflows`
invocation transparently appends `--model opus`:

```bash
# ~/.zshrc or ~/.bashrc
alias orchestrate-opus='claude /orchestrating-workflows'

# Or a function that forces --model opus on every call:
orchestrate-opus() {
    claude /orchestrating-workflows "$@" --model opus
}
```

Note that this does not affect main-context steps
(`documenting-*`, `documenting-qa`, `executing-qa`) — those always run on
whatever model the parent conversation is using.

### Option 3: Per-step forced upgrade

If you only want to force specific steps to Opus (for example, you trust
Sonnet for chore and bug execution but want Opus for feature planning),
use `--model-for`:

```bash
/orchestrating-workflows FEAT-001 \
    --model-for creating-implementation-plans:opus \
    --model-for reviewing-requirements:opus
```

This lets you adopt the adaptive policy for most steps while selectively
forcing tier for the ones where you have empirical evidence that Sonnet
is insufficient.

### Option 4: Sticky per-workflow overrides (persisted in state file)

Between a `pause` and a `resume`, there are two **distinct** state-file
knobs, and they set **different** fields:

**4a — Upgrade the work-item complexity axis via `set-complexity`.**
This writes `.complexity` (the work-item axis input, FR-2a/FR-2b) and is
itself upgrade-only — if you raise complexity from `medium` to `high`,
all subsequent forks see the higher tier through the FR-3 walker:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-complexity FEAT-001 high
```

Use this when you want to re-classify the work item's difficulty, e.g.
because you discovered the scope is larger than the requirement doc
signals suggested.

**4b — Force a sticky soft override via `.modelOverride`.**
This writes the `.modelOverride` state field — a **soft**
override per FR-5 #4, so it is upgrade-only and respects baseline locks:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-model-override FEAT-001 opus
```

Use this when you want to force the whole workflow to a specific tier
without re-classifying the complexity signal.

Remember that both `.complexity` and `.modelOverride` are **soft** inputs
— they are upgrade-only and respect baseline locks (so neither can push
`finalizing-workflow` or the PR-creation fork above `haiku`). If you need
to downgrade below baseline or force a baseline-locked step above its
floor, use a **hard** override via `--model` at invocation time instead.

## Why requirement docs have no complexity/model-override frontmatter

FEAT-014 intentionally does not introduce a `complexity: high` or
`model-override: opus` field in requirement document frontmatter — see
FR-5 in the requirements doc for the full rationale, summarized here:

- **No existing frontmatter convention.** Feature, chore, and bug
  requirement documents in this repo start directly with a `# Heading`
  line — none of them carry YAML frontmatter. Adding a frontmatter block
  for a single feature would create a new authoring convention for three
  documenting skills.
- **Neither field is valid in any Claude Code frontmatter schema.**
  Subagent, skill, and plugin manifest schemas all have a different set
  of valid fields. A doc-check run against code.claude.com confirmed that
  `complexity` and `model-override` are not recognized anywhere.
- **Name collision with real schema fields.** Claude Code's subagent and
  skill frontmatter uses a field literally called `model` (accepting
  `sonnet`/`opus`/`haiku`/full-ID/`inherit`), and a separate field
  called `effort` (accepting `low`/`medium`/`high`/`max` for
  computational effort within a single invocation). A reader seeing
  `complexity: high` in a requirement doc could reasonably assume it
  maps to `effort` behavior, even though `effort` addresses a completely
  different layer (thinking budget within a model invocation, not which
  model is selected).
- **Single-use parser cost.** Adding a frontmatter parser to the
  orchestrator for two optional fields used nowhere else in the codebase
  is not worth the maintenance burden when the same outcome is available
  via CLI flags (`--model`, `--complexity`, `--model-for`) or the state
  file (`modelOverride`).

If per-document override becomes necessary in the future, an in-body
section (like the existing `## GitHub Issue` pattern) is more consistent
with the current "plain markdown" convention — see the Future Enhancements
section of the FEAT-014 requirements doc for details.

## Cross-references

- **`plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` "Model
  Selection" section** — the concise in-SKILL summary with the baseline
  and signal matrices, and override precedence table.
- **`requirements/features/FEAT-014-adaptive-model-selection.md`** —
  the full requirements doc with every FR, NFR, edge case, and worked
  example.
- **`${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh`** — the canonical
  shell implementation of the classifier, override walker, audit trail
  writer, retry helpers, and resume re-computation.
- **`scripts/__tests__/workflow-state.test.ts`** — unit tests for every
  signal extractor, override precedence level, baseline-lock interaction,
  retry path, and resume scenario.
- **`scripts/__tests__/orchestrating-workflows.test.ts`** — integration
  tests covering Examples A, B, C, and D from the requirements doc
  end-to-end against synthetic fixtures.
