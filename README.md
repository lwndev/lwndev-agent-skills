# Agent Skills

[![CI](https://github.com/lwndev/lwndev-marketplace/actions/workflows/ci.yml/badge.svg)](https://github.com/lwndev/lwndev-marketplace/actions/workflows/ci.yml)

A reference implementation for developing, building, and distributing custom Agent Skills for Claude Code as a plugin. Use this project as a template for creating your own skill development workflow.

## Getting Started

```bash
# Install dependencies
npm install

# Build the plugin
npm run build
```

## Plugin Installation

### Via marketplace

```bash
# Add the marketplace
/plugin marketplace add lwndev/lwndev-marketplace

# Install the plugin
/plugin install lwndev-sdlc@lwndev-plugins
```

### Via project settings

Add to your project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "lwndev-plugins": {
      "source": {
        "source": "github",
        "repo": "lwndev/lwndev-marketplace"
      }
    }
  },
  "enabledPlugins": {
    "lwndev-sdlc@lwndev-plugins": true
  }
}
```

## Included Skills

| Skill | Description |
|-------|-------------|
| **documenting-features** | Creates structured feature requirement documents with user stories, acceptance criteria, and functional/non-functional requirements |
| **creating-implementation-plans** | Transforms feature requirements into phased implementation plans with deliverables and success criteria |
| **implementing-plan-phases** | Executes implementation plan phases with branch management, progress tracking, and deliverable verification |
| **documenting-chores** | Creates lightweight documentation for maintenance tasks (refactoring, dependency updates, cleanup) |
| **executing-chores** | Executes chore workflows including branch creation, implementation, and PR creation |
| **documenting-bugs** | Creates structured bug report documents with root cause analysis and traceable acceptance criteria |
| **executing-bug-fixes** | Executes bug fix workflows from branch creation through pull request with root cause driven execution |

## Development

### Commands

```bash
npm run scaffold         # Create a new skill interactively
npm run build            # Validate and build plugin to dist/
npm test                 # Run all tests
npm run lint             # Check for linting issues
npm run lint:fix         # Auto-fix linting issues
npm run format           # Format code with Prettier
npm run format:check     # Check formatting
```

### Project Structure

```
├── src/skills/                        # Skill source directories
│   └── {skill-name}/
│       ├── SKILL.md                   # Required: YAML frontmatter + instructions
│       ├── assets/                    # Optional: Templates and static resources
│       └── references/                # Optional: Reference documentation
├── src/plugin/                        # Plugin metadata source
│   ├── plugin.json                    # Plugin manifest
│   └── README.md                      # Plugin README
├── .claude-plugin/
│   └── marketplace.json               # Marketplace manifest
├── scripts/                           # CLI scripts
│   ├── lib/                           # Shared utilities
│   └── __tests__/                     # Test suites
└── dist/lwndev-sdlc-plugin/          # Built plugin (gitignored)
    ├── .claude-plugin/plugin.json
    ├── skills/                        # All skill directories
    └── README.md
```

### Creating a New Skill

1. Run `npm run scaffold` and follow the prompts
2. Edit the generated `src/skills/{name}/SKILL.md` with your skill instructions
3. Add templates and reference docs as needed
4. Run `npm run build` to validate and build the plugin

### SKILL.md Format

```markdown
---
name: my-skill-name
description: Brief description of what the skill does
allowed-tools:
  - Read
  - Write
  - Bash
---

# My Skill

Instructions for Claude on how to use this skill...
```

## Dependencies

- **ai-skills-manager** - Programmatic API for skill validation (v1.8.0+)
- **@inquirer/prompts** - Interactive CLI prompts
- **chalk** - Colored console output
- **gray-matter** - YAML frontmatter parsing
