# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project develops, builds, and distributes custom Agent Skills for Claude Code as a plugin. Skills are authored in `src/skills/`, validated and assembled into a plugin directory by the build script, and distributed via a marketplace manifest for installation with `/plugin install`.

## Commands

### Skill Lifecycle
```bash
npm run scaffold        # Create new skill interactively
npm run build           # Validate skills and build plugin to dist/lwndev-sdlc-plugin/
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
The build script produces a Claude Code plugin: `scaffold → build → /plugin install`

- **scaffold.ts** - Creates new skill directories using `scaffold()` API from `ai-skills-manager`
- **build.ts** - Validates each skill with `validate()` API, then copies all validated skills into the plugin directory structure at `dist/lwndev-sdlc-plugin/`

### Plugin Output Structure
```
dist/lwndev-sdlc-plugin/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest (name: lwndev-sdlc)
├── skills/                  # All 7 skill directories
│   ├── documenting-features/
│   ├── creating-implementation-plans/
│   ├── implementing-plan-phases/
│   ├── documenting-chores/
│   ├── executing-chores/
│   ├── documenting-bugs/
│   └── executing-bug-fixes/
└── README.md
```

### Marketplace
The repository hosts a marketplace manifest at `.claude-plugin/marketplace.json` for plugin distribution. Users install via:
```bash
/plugin marketplace add lwndev/lwndev-marketplace
/plugin install lwndev-sdlc@lwndev-plugins
```

### Shared Library (`scripts/lib/`)
- **skill-utils.ts** - Core functions: `getSourceSkills()`, `pluginBuildExists()`
- **constants.ts** - Path constants: `SKILLS_SOURCE_DIR`, `DIST_DIR`, `PLUGIN_NAME`, `PLUGIN_OUTPUT_DIR`, `PLUGIN_SKILLS_DIR`, `PLUGIN_MANIFEST_DIR`, `PLUGIN_SOURCE_DIR`
- **prompts.ts** - CLI print utilities (`printSuccess`, `printError`, `printInfo`, `printWarning`)

### Skill Structure
Each skill in `src/skills/` contains:
```
skill-name/
├── SKILL.md      # Required: YAML frontmatter (name, description) + markdown instructions
├── assets/       # Optional: Output templates and static resources
└── references/   # Optional: Reference documentation
```

### Existing Skills
Seven skills exist that form three workflow chains:
1. **documenting-features** → **creating-implementation-plans** → **implementing-plan-phases**
2. **documenting-chores** → **executing-chores**
3. **documenting-bugs** → **executing-bug-fixes**

## Key Patterns

- Skill validation uses the `ai-skills-manager` programmatic API (`validate()`)
- Skills use YAML frontmatter in SKILL.md for metadata extraction
- Tests run sequentially (`maxWorkers: 1`) to prevent race conditions with shared `src/skills/` and `dist/` directories
- Plugin source files (`plugin.json`, `README.md`) live in `src/plugin/` and are copied to `dist/` during build
