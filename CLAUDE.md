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
npm test                # Run all tests
npm run test:watch      # Run tests in watch mode
npm run test:coverage   # Run tests with coverage reporting
npm test -- --testPathPatterns=<pattern>  # Run specific test file
npm run test-skill      # Drive a single skill end-to-end against a fixture
npm run lint            # Check for linting issues
npm run lint:fix        # Auto-fix linting issues
npm run format          # Format code with Prettier
npm run format:check    # Check formatting
```

When running tests, always scope to the relevant file (`--testPathPatterns=<pattern>`) and pipe output through `tail` (e.g. `| tail -50`) or redirect to a file to avoid flooding context with full run output.

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
    ├── agents/                 # Subagent definitions (qa-verifier, qa-reconciliation-agent)
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
Thirteen skills exist that form three workflow chains. The `orchestrating-workflows` skill drives any chain end-to-end from a single invocation, sequencing sub-skill calls, forking per-step subagents, and persisting state across pause points (plan approval, PR review). The `reviewing-requirements` skill appears at multiple points and selects its mode (standard, test-plan reconciliation, code-review reconciliation) automatically based on context. The `managing-work-items` skill is invoked inline (not as a numbered step) for issue-tracker operations. Reconciliation steps are optional but recommended.
1. **documenting-features** → **reviewing-requirements** → **creating-implementation-plans** → **documenting-qa** → **reviewing-requirements** *(reconciliation)* → **implementing-plan-phases** → *PR review* → **reviewing-requirements** *(reconciliation)* → **executing-qa** → **finalizing-workflow**
2. **documenting-chores** → **reviewing-requirements** → **documenting-qa** → **reviewing-requirements** *(reconciliation)* → **executing-chores** → *PR review* → **reviewing-requirements** *(reconciliation)* → **executing-qa** → **finalizing-workflow**
3. **documenting-bugs** → **reviewing-requirements** → **documenting-qa** → **reviewing-requirements** *(reconciliation)* → **executing-bug-fixes** → *PR review* → **reviewing-requirements** *(reconciliation)* → **executing-qa** → **finalizing-workflow**

## Key Patterns

- Skill validation uses the `ai-skills-manager` programmatic API (`validate()`)
- Skills use YAML frontmatter in SKILL.md for metadata extraction
- Tests run sequentially (`fileParallelism: false` in `vitest.config.ts`) to prevent race conditions with shared `plugins/` directories
- Plugin discovery is filesystem-driven: directories under `plugins/` with `.claude-plugin/plugin.json` are treated as plugins
- No build output — plugins live in their final structure under `plugins/` and marketplace source paths point directly to them

## Skill Authoring: Prefer Scripts Over Prose

Push behavior into deterministic scripts, not SKILL.md prose. This is a first-class authoring principle for every skill in this repo — it keeps runs reproducible, keeps token cost down, and makes behavior testable.

- **Logic lives in `skills/<name>/scripts/`, not in SKILL.md.** SKILL.md describes the contract (inputs, outputs, when to invoke); scripts implement it. Prefer a single script entry point the skill calls (e.g. `workflow-state.sh <subcommand>`) over inline `jq`, `git`, `date`, or arithmetic in SKILL.md.
- **Derived data must be computed in scripts.** Durations, counts, gaps, aggregations, totals, rendered reports — anything the model could "reconstruct" — is computed by the script and emitted as the source of truth. Do not rely on the model to do the math.
- **Every script behavior needs bats coverage.** New subcommands and branches land alongside the existing bats suites (`*.bats` next to the script). If a behavior matters, it has a test. If it has a test, the model doesn't need to remember it.
- **Keep SKILL.md lean.** SKILL.md is a hot path for token cost on every invocation. Long-form logic belongs in scripts; long-form detail belongs under `references/`. A SKILL.md change should typically be a one-line invocation swap plus a contract note — not a procedure rewrite.
- **Load-bearing output from scripts is contract.** Tagged lines (`[info]`, `[warn]`, `[model]`, FR-14 echoes, report paths) are the script's structured log and the skill emits them verbatim. Do not paraphrase.
- **Write prose at Caveman "Lite" grunt level to cut tokens.** Adopt the style described at https://github.com/juliusbrussee/caveman: drop filler, keep grammar. Professional tone, no fluff. Contrast: *"Your component re-renders because you create a new object reference each render. Inline object props fail shallow comparison every time. Wrap it in `useMemo`."* (Lite) vs. the Full-grunt *"New object ref each render. Inline object prop = new ref = re-render. Wrap in `useMemo`."* Lite keeps articles and full sentences so the guidance still reads as technical writing, but strips hedges, restatements, and narration. Apply this to SKILL.md bodies, `references/` docs, issue descriptions, commit messages, and PR bodies in this repo. Load-bearing carve-outs (orchestrator error messages, security warnings, interactive prompts, structured log lines) stay verbatim — Lite does not override contracts.
