# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository is a plugin marketplace for Claude Code. Plugins are authored under `src/plugins/`, each containing skills that are validated and assembled by the build script, then distributed via a marketplace manifest for installation with `/plugin install`.

## Commands

### Plugin Lifecycle
```bash
npm run scaffold        # Create new skill interactively (prompts for plugin if multiple exist)
npm run build           # Validate and build all plugins to dist/
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

### Plugin Build Pipeline
The build script discovers and builds all plugins: `scaffold → build → /plugin install`

- **scaffold.ts** - Creates new skill directories using `scaffold()` API from `ai-skills-manager`. Discovers plugins via `getSourcePlugins()` and auto-selects if only one exists.
- **build.ts** - Discovers all plugins under `src/plugins/`, validates each plugin's skills with `validate()` API, then copies validated skills into per-plugin output directories under `dist/`.

### Source Structure
```
src/plugins/
└── lwndev-sdlc/               # Each plugin is self-contained
    ├── plugin.json             # Plugin manifest (name, version, metadata)
    ├── README.md               # Plugin documentation
    └── skills/                 # Skill directories
        ├── documenting-features/
        ├── creating-implementation-plans/
        ├── implementing-plan-phases/
        ├── documenting-chores/
        ├── executing-chores/
        ├── documenting-bugs/
        └── executing-bug-fixes/
```

### Plugin Output Structure
Each plugin builds to `dist/<plugin-name>-plugin/`:
```
dist/lwndev-sdlc-plugin/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── (all skill directories)
└── README.md
```

### Marketplace
The repository hosts a marketplace manifest at `.claude-plugin/marketplace.json` for plugin distribution. Users install via:
```bash
/plugin marketplace add lwndev/lwndev-marketplace
/plugin install lwndev-sdlc@lwndev-plugins
```

### Shared Library (`scripts/lib/`)
- **constants.ts** - `PLUGINS_SOURCE_DIR`, `DIST_DIR`, and parameterized helpers: `getPluginSourceDir()`, `getPluginSkillsSourceDir()`, `getPluginOutputDir()`, `getPluginSkillsOutputDir()`, `getPluginManifestOutputDir()`
- **skill-utils.ts** - Core functions: `getSourcePlugins()`, `getSourceSkills(pluginName)`, `pluginBuildExists(pluginName)`
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
Seven skills exist that form three workflow chains:
1. **documenting-features** → **creating-implementation-plans** → **implementing-plan-phases**
2. **documenting-chores** → **executing-chores**
3. **documenting-bugs** → **executing-bug-fixes**

## Key Patterns

- Skill validation uses the `ai-skills-manager` programmatic API (`validate()`)
- Skills use YAML frontmatter in SKILL.md for metadata extraction
- Tests run sequentially (`maxWorkers: 1`) to prevent race conditions with shared `src/plugins/` and `dist/` directories
- Plugin discovery is filesystem-driven: directories under `src/plugins/` with a `plugin.json` are treated as plugins
- Constants are parameterized functions that accept a plugin name, not hardcoded values
