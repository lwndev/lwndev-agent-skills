# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository is a plugin marketplace for Claude Code. Plugins live under `plugins/` in their final Claude Code-consumable structure, validated by the build script and distributed via a marketplace manifest for installation with `/plugin install`.

## Commands

### Plugin Lifecycle
```bash
npm run scaffold        # Create new skill interactively (prompts for plugin if multiple exist)
npm run validate           # Validate all plugins
```

### Development
```bash
npm test                # Run all tests
npm test -- --testPathPatterns=<pattern>  # Run specific test file
npm run lint            # Check for linting issues
npm run lint:fix        # Auto-fix linting issues
npm run format          # Format code with Prettier
npm run format:check    # Check formatting
```

## Architecture

### Plugin Validation Pipeline
The build script discovers and validates all plugins: `scaffold → build (validate) → /plugin install`

- **scaffold.ts** - Creates new skill directories using `scaffold()` API from `ai-skills-manager`. Discovers plugins via `getSourcePlugins()` and auto-selects if only one exists. Supports `--plugin <name>` flag.
- **build.ts** - Discovers all plugins under `plugins/`, validates each plugin's skills with `validate()` API in-place. No copy step — plugins are already in their final structure.

### Plugin Structure
Each plugin under `plugins/` is self-contained and directly consumable by Claude Code:
```
plugins/
└── lwndev-sdlc/
    ├── .claude-plugin/
    │   └── plugin.json         # Plugin manifest (name, version, metadata)
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
- **constants.ts** - `PLUGINS_DIR` and parameterized helpers: `getPluginDir()`, `getPluginSkillsDir()`, `getPluginManifestDir()`
- **skill-utils.ts** - Core functions: `getSourcePlugins()`, `getSourceSkills(pluginName)`
- **prompts.ts** - CLI print utilities (`printSuccess`, `printError`, `printInfo`, `printWarning`)

### Skill Structure
Each skill in a plugin's `skills/` directory contains:
```
skill-name/
├── SKILL.md      # Required: YAML frontmatter (name, description) + markdown instructions
├── assets/       # Optional: Output templates and static resources
└── references/   # Optional: Reference documentation
```

### Existing Skills (lwndev-sdlc plugin)
Eleven skills exist that form three workflow chains:
1. **documenting-features** → **reviewing-requirements** → **documenting-qa** → **creating-implementation-plans** → **implementing-plan-phases** → **executing-qa** → **finalizing-workflow**
2. **documenting-chores** → **reviewing-requirements** → **documenting-qa** → **executing-chores** → **executing-qa** → **finalizing-workflow**
3. **documenting-bugs** → **reviewing-requirements** → **documenting-qa** → **executing-bug-fixes** → **executing-qa** → **finalizing-workflow**

## Key Patterns

- Skill validation uses the `ai-skills-manager` programmatic API (`validate()`)
- Skills use YAML frontmatter in SKILL.md for metadata extraction
- Tests run sequentially (`fileParallelism: false` in `vitest.config.ts`) to prevent race conditions with shared `plugins/` directories
- Plugin discovery is filesystem-driven: directories under `plugins/` with `.claude-plugin/plugin.json` are treated as plugins
- No build output — plugins live in their final structure under `plugins/` and marketplace source paths point directly to them
