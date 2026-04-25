# `creating-implementation-plans` — Skill-scoped Scripts

This directory holds the skill-scoped shell scripts for `creating-implementation-plans`. Each script implements a single deterministic operation with a defined CLI contract (positional args, exit codes, stdout shape). The skill invokes these scripts instead of re-describing the operation in SKILL.md prose.

## Invocation Convention

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/<name>.sh" [args…]
```

Scripts read and write the consumer repo's filesystem relative to `$PWD` — that is, the consumer project where `requirements/features/` and `requirements/implementation/` live.

## Script Table

| Script | FR | Purpose |
|---|---|---|
| `render-plan-scaffold.sh` | FEAT-029 FR-1 | Render a multi-feature plan skeleton from one or more `FEAT-NNN` IDs to `requirements/implementation/<primary-FEAT>-<slug>.md`. Refuses to overwrite. `--enforce-phase-budget` invokes FR-5 as a gate. |
| `validate-plan-dag.sh` | FEAT-029 FR-2 | Validate the per-phase dependency graph: detect cycles and unresolved `**Depends on:** Phase N` references via Kahn topological sort. Fence-aware. |
| `phase-complexity-budget.sh` | FEAT-029 FR-3 | Score each phase block (or one phase via `--phase N`) against the budget table; emit per-phase tier (`haiku`/`sonnet`/`opus`) JSON. Honours `**ComplexityOverride:** <tier>` clamps. Budget table tunable at the top of the script. |
| `split-phase-suggest.sh` | FEAT-029 FR-4 | Advisory: emit a JSON 2–3-way split for an over-budget phase, preserving step ordering and `**Depends on Step N**` annotations. Does not write the plan. |
| `validate-phase-sizes.sh` | FEAT-029 FR-5 | Gate: fail if any phase exceeds its budget without a `**ComplexityOverride:**` clamp. Wraps FR-3; called as the last step of FR-1 when `--enforce-phase-budget` is passed and as a verification-checklist item in SKILL.md. |

## Bats Fixture Layout

Each script has an adjacent bats fixture under `tests/`:

```
plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/
├── <script>.sh
└── tests/
    ├── <script>.bats
    └── fixtures/
```

Fixtures cover happy path, every documented error exit code, fence-awareness, and idempotency / override-clamp paths where applicable. Fixtures isolate filesystem state via `mktemp -d` in `setup()` and clean up in `teardown()`.

## Running Tests Locally

```bash
bats plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/*.bats
```

Install `bats-core` via `brew install bats-core` if it is not already present.

## jq Fallback

`phase-complexity-budget.sh` and `split-phase-suggest.sh` emit JSON. They use `jq` if available for safe escaping; if `jq` is absent they fall back to hand-assembled JSON with explicit string escaping. `jq` is therefore recommended but not required.
