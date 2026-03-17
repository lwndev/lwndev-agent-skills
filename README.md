# LWNDEV Plugin Marketplace

[![CI](https://github.com/lwndev/lwndev-marketplace/actions/workflows/ci.yml/badge.svg)](https://github.com/lwndev/lwndev-marketplace/actions/workflows/ci.yml)

A marketplace for distributing Claude Code plugins. Add the marketplace to access SDLC workflow plugins for documenting, planning, and executing features, chores, and bug fixes.

## Adding the Marketplace

```bash
/plugin marketplace add lwndev/lwndev-marketplace
```

## Available Plugins

| Plugin | Description |
|--------|-------------|
| **lwndev-sdlc** | SDLC workflow skills for documenting, planning, and executing features, chores, and bug fixes |

### Installing a Plugin

```bash
/plugin install lwndev-sdlc@lwndev-plugins
```

Or add to your project's `.claude/settings.json`:

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

## Development

### Commands

```bash
npm run scaffold         # Create a new skill interactively
npm run build            # Validate and build all plugins to dist/
npm test                 # Run all tests
npm run lint             # Check for linting issues
npm run lint:fix         # Auto-fix linting issues
npm run format           # Format code with Prettier
npm run format:check     # Check formatting
```

### Project Structure

```
├── src/plugins/                       # Plugin source directories
│   └── lwndev-sdlc/                  # SDLC workflow plugin
│       ├── plugin.json               # Plugin manifest
│       ├── README.md                  # Plugin documentation
│       └── skills/                    # Skill directories
│           └── {skill-name}/
│               ├── SKILL.md           # Required: YAML frontmatter + instructions
│               ├── assets/            # Optional: Templates and static resources
│               └── references/        # Optional: Reference documentation
├── .claude-plugin/
│   └── marketplace.json               # Marketplace manifest
├── scripts/                           # CLI scripts
│   ├── lib/                           # Shared utilities
│   └── __tests__/                     # Test suites
└── dist/                              # Built plugins (gitignored)
    └── lwndev-sdlc-plugin/
```

### Adding a New Plugin

1. Create `src/plugins/{plugin-name}/` with `plugin.json`, `README.md`, and a `skills/` directory
2. Add skills under `src/plugins/{plugin-name}/skills/` (use `npm run scaffold`)
3. Add the plugin entry to `.claude-plugin/marketplace.json`
4. Run `npm run build` to validate and build

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
