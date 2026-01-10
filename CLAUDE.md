# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project is used to develop multiple Agent Skills for Claude Code. It includes TypeScript CLI scripts that invoke the `ai-skills-manager` CLI (via the `asm` command) to create, build, install, and manage custom AI Agent Skills that extend Claude's capabilities with domain-specific workflows.

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

- **scaffold.ts** - Creates new skill directories via `asm scaffold`
- **build.ts** - Validates all skills with `asm validate`, then packages to `dist/*.skill`
- **install.ts** - Installs from `dist/` to project (`.claude/skills/`) or personal (`~/.claude/skills/`) scope
- **update.ts** / **uninstall.ts** - Manage installed skills

### Shared Library (`scripts/lib/`)
- **skill-utils.ts** - Core functions: `getSourceSkills()`, `getInstalledSkills(scope)`, `packagedSkillExists()`
- **constants.ts** - Path constants for `src/skills`, `dist`, `.claude/skills`
- **prompts.ts** - Interactive CLI utilities using `@inquirer/prompts`

### Skill Structure
Each skill in `src/skills/` contains:
```
skill-name/
├── SKILL.md      # Required: YAML frontmatter (name, description) + markdown instructions
├── templates/    # Optional: Output templates
└── reference/    # Optional: Reference documentation
```

### Existing Skills
Six skills exist that form a workflow chain:
1. **documenting-features** → **creating-implementation-plans** → **implementing-plan-phases**
2. **documenting-chores** → **executing-chores**
3. **managing-git-worktrees** (parallel development support)

## Key Patterns

- All skill operations delegate to `asm` CLI commands
- Skills use YAML frontmatter in SKILL.md for metadata extraction
- Tests run sequentially (`maxWorkers: 1`) to prevent race conditions with shared `src/skills/` and `dist/` directories
- Interactive prompts use scope selection: "project" vs "personal" installation paths
