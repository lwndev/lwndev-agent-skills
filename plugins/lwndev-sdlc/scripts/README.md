# Plugin Shared Scripts

This directory holds cross-cutting shell utilities that every SDLC skill in the `lwndev-sdlc` plugin depends on. Each script implements a single deterministic operation with a defined CLI contract (positional args, exit codes, stdout shape). Skills invoke these scripts instead of re-describing the operation in prose.

## Invocation Convention

Skills invoke scripts via the absolute path:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh" [args…]
```

`${CLAUDE_PLUGIN_ROOT}` is the environment variable Claude Code sets when a plugin skill executes. Scripts are **not** on `PATH` — callers always use the absolute path. Scripts that call sibling scripts internally resolve them via `${BASH_SOURCE%/*}`, so they work regardless of the caller's CWD.

Scripts that read or write the consumer repo's filesystem (`next-id.sh`, `resolve-requirement-doc.sh`, `check-acceptance.sh`, `checkbox-flip-all.sh`) operate relative to `$PWD` — that is, the consumer project where the requirement docs live.

## Script Table

| Script | FR | Purpose |
|---|---|---|
| `next-id.sh` | FR-1 | Allocate the next zero-padded requirement-doc ID for `FEAT`/`CHORE`/`BUG`. |
| `slugify.sh` | FR-2 | Produce a kebab-case slug from a freeform title (stopwords dropped, first 4 tokens). |
| `resolve-requirement-doc.sh` | FR-3 | Map a requirement ID (`FEAT-020`) to its unique document path. |
| `build-branch-name.sh` | FR-4 | Assemble the canonical branch name `<type>/<ID>-<slug>`. |
| `ensure-branch.sh` | FR-5 | Idempotently place the working tree on the named branch. |
| `check-acceptance.sh` | FR-6 | Flip a single acceptance-criteria checkbox, fence-aware. |
| `checkbox-flip-all.sh` | FR-7 | Flip every unchecked checkbox inside a named section, fence-aware. |
| `commit-work.sh` | FR-8 | Emit a conventional-commits commit (caller stages). |
| `create-pr.sh` | FR-9 | Push the current branch and create a PR from the template. |
| `branch-id-parse.sh` | FR-10 | Classify a branch name into work-item `{id, type, dir}` JSON. |
| `prepare-fork.sh` | FEAT-021 | Run the FEAT-014 pre-fork ceremony (SKILL.md readability check, tier resolution, audit-trail write, FR-14 echo line) and print the resolved tier. |

## Bats Fixture Layout

Each script has an adjacent bats fixture under `tests/`:

```
plugins/lwndev-sdlc/scripts/
├── <script>.sh
└── tests/
    └── <script>.bats
```

Fixtures cover happy path, every documented error exit code, idempotency (where applicable), and fence-awareness (where applicable). Fixtures isolate filesystem state via `mktemp -d` in `setup()` and clean up in `teardown()`. Git-dependent fixtures create synthetic repos in `setup()`.

## Running Tests Locally

```bash
bats plugins/lwndev-sdlc/scripts/tests/*.bats
```

Install `bats-core` via `brew install bats-core` if it is not already present.

## jq Fallback

`branch-id-parse.sh` emits JSON. It uses `jq` if available for safe escaping; if `jq` is absent it falls back to hand-assembled JSON with explicit string escaping. The bats fixture exercises the fallback by shadowing `jq` in `PATH`. `jq` is therefore recommended but not required.

## Shellcheck Gate

All scripts pass `shellcheck -S warning` with zero warnings. Run before committing:

```bash
shellcheck -S warning plugins/lwndev-sdlc/scripts/*.sh
```
