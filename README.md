# Agent Skills

[![CI](https://github.com/lwndev/lwndev-agent-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/lwndev/lwndev-agent-skills/actions/workflows/ci.yml)

A reference implementation for [`ai-skills-manager`](https://github.com/anthropics/ai-skills-manager), demonstrating how to develop, build, and manage custom Agent Skills for Claude Code. Use this project as a template for creating your own skill development workflow.

## Getting Started

```bash
# Install dependencies
npm install

# Build all skills
npm run build

# Install skills to Claude Code
npm run install-skills
```

## Included Skills

| Skill | Description |
|-------|-------------|
| **documenting-features** | Creates structured feature requirement documents with user stories, acceptance criteria, and functional/non-functional requirements |
| **creating-implementation-plans** | Transforms feature requirements into phased implementation plans with deliverables and success criteria |
| **implementing-plan-phases** | Executes implementation plan phases with branch management, progress tracking, and deliverable verification |
| **documenting-chores** | Creates lightweight documentation for maintenance tasks (refactoring, dependency updates, cleanup) |
| **executing-chores** | Executes chore workflows including branch creation, implementation, and PR creation |
| **managing-git-worktrees** | Creates and manages Git worktrees for parallel development workflows |

## Skill Lifecycle Commands

```bash
npm run scaffold         # Create a new skill interactively
npm run build            # Validate and package all skills to dist/
npm run install-skills   # Install packaged skills to Claude Code
npm run update-skills    # Update an installed skill
npm run uninstall-skills # Remove installed skills
```

### Installation Scopes

Skills can be installed to two locations:
- **Project scope** (`.claude/skills/`) - Available only in this project
- **Personal scope** (`~/.claude/skills/`) - Available across all projects

## Development

```bash
npm test                # Run all tests
npm run lint            # Check for linting issues
npm run lint:fix        # Auto-fix linting issues
npm run format          # Format code with Prettier
npm run format:check    # Check formatting
```

## Project Structure

```
├── src/skills/           # Skill source directories
│   └── {skill-name}/
│       ├── SKILL.md      # Required: YAML frontmatter + instructions
│       ├── assets/       # Optional: Templates and static resources
│       └── references/   # Optional: Reference documentation
├── scripts/              # CLI scripts
│   ├── lib/              # Shared utilities
│   └── __tests__/        # Test suites
├── dist/                 # Built .skill packages
└── .claude/skills/       # Project-installed skills
```

## Creating a New Skill

1. Run `npm run scaffold` and follow the prompts
2. Edit the generated `src/skills/{name}/SKILL.md` with your skill instructions
3. Add templates and reference docs as needed
4. Run `npm run build` to validate and package
5. Run `npm run install-skills` to install to Claude Code

### SKILL.md Format

```markdown
---
name: my-skill-name
description: Brief description of what the skill does
allowed_tools:
  - Read
  - Write
  - Bash
---

# My Skill

Instructions for Claude on how to use this skill...
```

## Dependencies

- **ai-skills-manager** - Core CLI for skill operations (`asm` command)
- **@inquirer/prompts** - Interactive CLI prompts
- **chalk** - Colored console output
- **gray-matter** - YAML frontmatter parsing
