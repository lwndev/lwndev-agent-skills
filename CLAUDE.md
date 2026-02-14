# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project is a reference implementation for `ai-skills-manager`, demonstrating how to develop, build, and manage custom Agent Skills for Claude Code. It includes TypeScript CLI scripts that invoke the `asm` command to create, build, install, and manage skills that extend Claude's capabilities with domain-specific workflows.

## Commands

### Skill Lifecycle
```bash
npm run scaffold        # Create new skill interactively
npm run build           # Validate and package all skills to dist/
npm run install-skills  # Install packaged skills (interactive)
npm run update-skills   # Update installed skill (interactive)
npm run uninstall-skills # Remove installed skills (interactive)
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

### Script Pipeline
The scripts implement a skill lifecycle: `scaffold → build → install/update/uninstall`

Scripts use the `ai-skills-manager` programmatic API (v1.6.0+) for all operations:

- **scaffold.ts** - Creates new skill directories using `scaffold()` API
- **build.ts** - Validates with `validate()` and packages with `createPackage()` to `dist/*.skill`
- **install.ts** - Installs from `dist/` using `install()` API to project or personal scope
- **update.ts** - Updates installed skills using `update()` API
- **uninstall.ts** - Removes skills using `uninstall()` API

### Shared Library (`scripts/lib/`)
- **skill-utils.ts** - Core functions: `getSourceSkills()`, `getInstalledSkills(scope)` (uses `list()` API), `packagedSkillExists()`
- **constants.ts** - Path constants for `src/skills`, `dist`, `.claude/skills`
- **prompts.ts** - Interactive CLI utilities using `@inquirer/prompts`

### Skill Structure
Each skill in `src/skills/` contains:
```
skill-name/
├── SKILL.md      # Required: YAML frontmatter (name, description) + markdown instructions
├── assets/       # Optional: Output templates and static resources
└── references/   # Optional: Reference documentation
```

### Existing Skills
Five skills exist that form a workflow chain:
1. **documenting-features** → **creating-implementation-plans** → **implementing-plan-phases**
2. **documenting-chores** → **executing-chores**

## Key Patterns

- All skill operations use the `ai-skills-manager` programmatic API (not CLI)
- Skills use YAML frontmatter in SKILL.md for metadata extraction
- Tests run sequentially (`maxWorkers: 1`) to prevent race conditions with shared `src/skills/` and `dist/` directories
- Interactive prompts use scope selection: "project" vs "personal" installation paths
