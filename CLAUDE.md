# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository is a plugin marketplace for Claude Code. Plugins live under `plugins/` in their final Claude Code-consumable structure, validated by the build script and distributed via a marketplace manifest for installation with `/plugin install`.

## Commands

### Plugin Lifecycle
```bash
npm run scaffold        # Create new skill interactively (prompts for plugin if multiple exist)
npm run validate        # Validate all plugins
npm run release         # Run the plugin release workflow (version bump, changelog, tag)
npm run release:tag     # Tag-only operations for an already-prepared release
```

### Development
```bash
npm test                # Run all tests (Vitest + Bats)
npm run test:unit       # Run Vitest only (tests/unit/**/*.test.ts)
npm run test:bats       # Run Bats only (tests/bats/**/*.bats)
npm run test:watch      # Run Vitest in watch mode
npm run test:coverage   # Run Vitest with coverage reporting
npm test -- --testPathPatterns=<pattern>  # Run specific Vitest file
npx bats tests/bats/<path>                # Run specific Bats file or subtree
npm run test-skill      # Drive a single skill end-to-end against a fixture
npm run lint            # Check for linting issues
npm run lint:fix        # Auto-fix linting issues
npm run format          # Format code with Prettier
npm run format:check    # Check formatting
```

When running tests, always scope to the relevant file (`--testPathPatterns=<pattern>` for Vitest, a path argument for `npx bats`) and pipe output through `tail` (e.g. `| tail -50`) or redirect to a file to avoid flooding context with full run output. Bats ships as an npm devDep (`^1.13.0`); contributors get `npx bats` automatically after `npm install`. The full-suite `test:bats` script parallelizes across files via `bats --jobs 8`, which requires GNU parallel (`brew install parallel` on macOS, `apt-get install parallel` on Debian/Ubuntu); a single-file `npx bats <path>` invocation does not need it.

## Architecture

### Plugin Validation Pipeline
The build script discovers and validates all plugins: `scaffold → build (validate) → /plugin install`

- **scaffold.ts** - Creates new skill directories using `scaffold()` API from `ai-skills-manager`. Discovers plugins via `getSourcePlugins()` and auto-selects if only one exists. Supports `--plugin <name>` flag.
- **build.ts** - Discovers all plugins under `plugins/`, validates each plugin's skills with `validate()` API in-place. No copy step — plugins are already in their final structure.
- **release.ts** / **release-tag.ts** - Plugin release automation: version bumping, changelog generation from conventional commits, marketplace manifest updates, and git tagging.
- **test-skill.ts** - Exercises a single skill against a fixture for development feedback without going through a full workflow.

### Plugin Structure
Each plugin under `plugins/` is self-contained and directly consumable by Claude Code:
```
plugins/
└── lwndev-sdlc/
    ├── .claude-plugin/
    │   └── plugin.json         # Plugin manifest (name, version, metadata)
    ├── agents/                 # Subagent definitions (empty — agents replaced by scripts in FEAT-030)
    ├── skills/                 # Skill directories
    │   ├── documenting-features/
    │   ├── reviewing-requirements/
    │   ├── creating-implementation-plans/
    │   ├── implementing-plan-phases/
    │   ├── documenting-chores/
    │   ├── executing-chores/
    │   ├── documenting-bugs/
    │   ├── executing-bug-fixes/
    │   ├── documenting-qa/
    │   ├── executing-qa/
    │   ├── managing-work-items/
    │   ├── orchestrating-workflows/
    │   └── finalizing-workflow/
    └── README.md               # Plugin documentation
```

### Marketplace
The repository hosts a marketplace manifest at `.claude-plugin/marketplace.json` for plugin distribution. Source paths point directly to committed `plugins/` directories. Users install via:
```bash
/plugin marketplace add lwndev/lwndev-marketplace
/plugin install lwndev-sdlc@lwndev-plugins
```

### Shared Library (`scripts/lib/`)
- **constants.ts** - `PLUGINS_DIR` and parameterized helpers: `getPluginDir()`, `getPluginSkillsDir()`, `getPluginManifestDir()`, `getPluginAgentsDir()`
- **skill-utils.ts** - Core functions: `getSourcePlugins()`, `getSourceSkills(pluginName)`
- **prompts.ts** - CLI print utilities (`printSuccess`, `printError`, `printInfo`, `printWarning`) and `truncate()`
- **plugin-manifest.ts** - Manifest I/O: `readPluginManifest()`, `writePluginManifest()`, `readMarketplaceManifest()`, `writeMarketplaceManifest()`, `getMarketplacePluginEntry()`
- **git-utils.ts** - Git helpers used by the release scripts: `isWorkingTreeClean()`, `getCurrentBranch()`, `getDefaultBranch()`, `getTagsForPlugin()`, `getLatestTagForPlugin()`, `getCommitsSinceTag()`, `filterNoiseCommits()`, `tagExists()`

### Skill Structure
Each skill in a plugin's `skills/` directory contains:
```
skill-name/
├── SKILL.md      # Required: YAML frontmatter (name, description) + markdown instructions
├── assets/       # Optional: Output templates and static resources
└── references/   # Optional: Reference documentation
```

### Existing Skills (lwndev-sdlc plugin)
Fourteen skills exist that form three workflow chains. The `orchestrating-workflows` skill drives any chain end-to-end from a single invocation, sequencing sub-skill calls, forking per-step subagents, and persisting state across pause points (plan approval, PR review, QA verdict). The `reviewing-requirements` skill appears at multiple points and selects its mode (standard, test-plan reconciliation, code-review reconciliation) automatically based on context. The `managing-work-items` skill is invoked inline (not as a numbered step) for issue-tracker operations. Reconciliation steps are optional but recommended.

After `executing-qa`, the orchestrator branches on verdict:
- `PASS` (first run) or `EXPLORATORY-ONLY` → advance to `finalizing-workflow`.
- `ISSUES-FOUND` → fork `addressing-qa-findings` (fix phase); re-invoke `executing-qa` (re-QA mode); on `PASS` → fork `addressing-qa-findings` (adopt phase) → advance. Loop cap: 2 fix attempts (configurable via `--qa-loop-cap`). On exhaustion, pause with `qa-loop-exhausted`.
- `ERROR` → pause with `qa-error`.

1. **documenting-features** → **reviewing-requirements** → **creating-implementation-plans** → **documenting-qa** → **reviewing-requirements** *(reconciliation)* → **implementing-plan-phases** → *PR review* → **reviewing-requirements** *(reconciliation)* → **executing-qa** → *[verdict-branch]* → **addressing-qa-findings** *(if ISSUES-FOUND)* → **finalizing-workflow**
2. **documenting-chores** → **reviewing-requirements** → **documenting-qa** → **reviewing-requirements** *(reconciliation)* → **executing-chores** → *PR review* → **reviewing-requirements** *(reconciliation)* → **executing-qa** → *[verdict-branch]* → **addressing-qa-findings** *(if ISSUES-FOUND)* → **finalizing-workflow**
3. **documenting-bugs** → **reviewing-requirements** → **documenting-qa** → **reviewing-requirements** *(reconciliation)* → **executing-bug-fixes** → *PR review* → **reviewing-requirements** *(reconciliation)* → **executing-qa** → *[verdict-branch]* → **addressing-qa-findings** *(if ISSUES-FOUND)* → **finalizing-workflow**

### QA Test Lifecycle

QA-authored tests are ephemeral by design: they are committed to the branch during `executing-qa`, consumed by `addressing-qa-findings`, and promoted (moved) into the regression suite by the adopt phase. They are NOT permanent fixtures and must not accumulate in the repo.

**Naming convention:**
- QA-phase files: `tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, `tests/bats/qa/qa-*.bats`
- Adopted (permanent) siblings: `{dir}/{base}.qa.{ext}` — placed next to the existing peer test for the same SUT
  - Example: `tests/unit/foo.test.ts` → adopted QA sibling: `tests/unit/foo.qa.test.ts`
  - Example: `tests/bats/shared/check-acceptance.bats` → adopted sibling: `tests/bats/shared/check-acceptance.qa.bats`

**Adoption:** `addressing-qa-findings/scripts/adopt-qa-test.sh` is the **sole** owner of QA-test deletion. It uses `git mv` to move a `qa-*.test.ts` (or `.bats`) to its `*.qa.*` sibling path. No other script or skill deletes `qa-*` files (FR-13 invariant).

**Safety-net:** `finalizing-workflow` runs a preflight check (`preflight-checks.sh`) that blocks merge if any tracked `qa-*` files remain on the branch (FR-9). The check uses `git ls-files` against the v1 glob set (`qa-*.test.ts`, `qa-*.test.js`, `qa-*.bats`). Untracked files do not block. Adopted `*.qa.*` siblings pass cleanly — only the `qa-*` prefix is checked.

**Lockstep constraint (Edge Case 17):** Enabling FR-9 safety-net globs for pytest (`qa-*.py`) and go-test (`qa-*.go`) must land in lockstep with FR-5 dispatch support for those frameworks in `adopt-qa-test.sh`. Do not enable one without the other.

**Length assertions over directories that may receive `*.qa.*` siblings** (e.g. `tests/bats/shared/`) must filter out `*.qa.bats` files before counting canonical peers, or use set-based parity checks instead of hard-coded totals. See `tests/unit/shared-scripts.test.ts` and `tests/unit/qa-BUG-016.test.ts` for examples.

## Key Patterns

- Skill validation uses the `ai-skills-manager` programmatic API (`validate()`)
- Skills use YAML frontmatter in SKILL.md for metadata extraction
- Tests run in parallel (`fileParallelism: true` in `vitest.config.ts`); any test that needs to mutate a skill or plugin tree must use `mkdtemp` outside `plugins/` (writing into the real `plugins/` tree races with other parallel test files). For tests that need to drive `npm run validate` against a fixture tree, set `PLUGINS_DIR=<tmp>` in the child env — `scripts/lib/constants.ts` reads it at module load.
- Plugin discovery is filesystem-driven: directories under `plugins/` with `.claude-plugin/plugin.json` are treated as plugins
- No build output — plugins live in their final structure under `plugins/` and marketplace source paths point directly to them

## Skill Authoring: Prefer Scripts Over Prose

Push behavior into deterministic scripts, not SKILL.md prose. This is a first-class authoring principle for every skill in this repo — it keeps runs reproducible, keeps token cost down, and makes behavior testable.

- **Logic lives in `skills/<name>/scripts/`, not in SKILL.md.** SKILL.md describes the contract (inputs, outputs, when to invoke); scripts implement it. Prefer a single script entry point the skill calls (e.g. `workflow-state.sh <subcommand>`) over inline `jq`, `git`, `date`, or arithmetic in SKILL.md.
- **Derived data must be computed in scripts.** Durations, counts, gaps, aggregations, totals, rendered reports — anything the model could "reconstruct" — is computed by the script and emitted as the source of truth. Do not rely on the model to do the math.
- **Every script behavior needs test coverage at the canonical leaf.** TS modules → Vitest under `tests/unit/<name>.test.ts`. Shell scripts → Bats under `tests/bats/skills/<skill>/<name>.bats` (per-skill) or `tests/bats/shared/<name>.bats` (shared/hook). Cross-runner shared fixtures go under `tests/fixtures/<skill>/` or `tests/fixtures/qa-fixture/`. New test files land at the canonical leaf — the layout validator (`scripts/validate-test-layout.ts`) and PreToolUse hook (`scripts/hooks/validate-test-layout-hook.ts`) block any commit or `Write`/`Edit` that misplaces them. If a behavior matters, it has a test. If it has a test, the model doesn't need to remember it.
- **Keep SKILL.md lean.** SKILL.md is a hot path for token cost on every invocation. Long-form logic belongs in scripts; long-form detail belongs under `references/`. A SKILL.md change should typically be a one-line invocation swap plus a contract note — not a procedure rewrite.
- **Load-bearing output from scripts is contract.** Tagged lines (`[info]`, `[warn]`, `[model]`, FR-14 echoes, report paths) are the script's structured log and the skill emits them verbatim. Do not paraphrase.
- **Write prose at Caveman "Lite" grunt level to cut tokens.** Adopt the style described at https://github.com/juliusbrussee/caveman: drop filler, keep grammar. Professional tone, no fluff. Contrast: *"Your component re-renders because you create a new object reference each render. Inline object props fail shallow comparison every time. Wrap it in `useMemo`."* (Lite) vs. the Full-grunt *"New object ref each render. Inline object prop = new ref = re-render. Wrap in `useMemo`."* Lite keeps articles and full sentences so the guidance still reads as technical writing, but strips hedges, restatements, and narration. Apply this to SKILL.md bodies, `references/` docs, issue descriptions, commit messages, and PR bodies in this repo. Load-bearing carve-outs (orchestrator error messages, security warnings, interactive prompts, structured log lines) stay verbatim — Lite does not override contracts.
