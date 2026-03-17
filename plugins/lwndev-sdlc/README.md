# lwndev-sdlc

SDLC workflow skills for Claude Code — documenting, planning, and executing features, chores, and bug fixes.

## Skills

| Skill | Description |
|-------|-------------|
| **documenting-features** | Creates structured feature requirement documents with user stories, acceptance criteria, and functional/non-functional requirements |
| **creating-implementation-plans** | Transforms feature requirements into phased implementation plans with deliverables and success criteria |
| **implementing-plan-phases** | Executes implementation plan phases with branch management, progress tracking, and deliverable verification |
| **documenting-chores** | Creates lightweight documentation for maintenance tasks (refactoring, dependency updates, cleanup) |
| **executing-chores** | Executes chore workflows including branch creation, implementation, and PR creation |
| **documenting-bugs** | Creates structured bug report documents with root cause analysis and traceable acceptance criteria |
| **executing-bug-fixes** | Executes bug fix workflows from branch creation through pull request with root cause driven execution |

## Installation

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

## Usage

Skills are invoked as slash commands, namespaced under the plugin:

```
/lwndev-sdlc:documenting-features
/lwndev-sdlc:creating-implementation-plans
/lwndev-sdlc:implementing-plan-phases
/lwndev-sdlc:documenting-chores
/lwndev-sdlc:executing-chores
/lwndev-sdlc:documenting-bugs
/lwndev-sdlc:executing-bug-fixes
```

## Workflow Chains

The skills form three workflow chains:

1. **Features**: `documenting-features` → `creating-implementation-plans` → `implementing-plan-phases`
2. **Chores**: `documenting-chores` → `executing-chores`
3. **Bugs**: `documenting-bugs` → `executing-bug-fixes`
