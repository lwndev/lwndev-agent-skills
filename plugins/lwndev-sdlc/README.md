# lwndev-sdlc

**Version:** 1.4.0 | **Released:** 2026-03-28

SDLC workflow skills for Claude Code — documenting, planning, and executing features, chores, and bug fixes with QA validation capabilities.

## Skills

| Skill | Description |
|-------|-------------|
| **documenting-features** | Creates structured feature requirement documents with user stories, acceptance criteria, and functional/non-functional requirements |
| **reviewing-requirements** | Validates requirement documents against the codebase and docs, catching incorrect references, inconsistencies, and gaps before implementation |
| **creating-implementation-plans** | Transforms feature requirements into phased implementation plans with deliverables and success criteria |
| **implementing-plan-phases** | Executes implementation plan phases with branch management, progress tracking, and deliverable verification |
| **documenting-chores** | Creates lightweight documentation for maintenance tasks (refactoring, dependency updates, cleanup) |
| **executing-chores** | Executes chore workflows including branch creation, implementation, and PR creation |
| **documenting-bugs** | Creates structured bug report documents with root cause analysis and traceable acceptance criteria |
| **executing-bug-fixes** | Executes bug fix workflows from branch creation through pull request with root cause driven execution |
| **documenting-qa** | Builds a QA test plan from requirements documents with completeness verification via ralph loop |
| **executing-qa** | Executes QA verification and documentation reconciliation from a test plan |
| **finalizing-workflow** | Merges the current PR, checks out main, fetches, and pulls — the terminal step in all workflow chains |

## Agents

| Agent | Model | Description |
|-------|-------|-------------|
| **qa-verifier** | Sonnet | Runs test suites, analyzes coverage, verifies code paths against acceptance criteria, and returns structured pass/fail verdicts. Used by `documenting-qa` and `executing-qa` skills via subagent delegation. |

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
/lwndev-sdlc:reviewing-requirements
/lwndev-sdlc:creating-implementation-plans
/lwndev-sdlc:implementing-plan-phases
/lwndev-sdlc:documenting-chores
/lwndev-sdlc:executing-chores
/lwndev-sdlc:documenting-bugs
/lwndev-sdlc:executing-bug-fixes
/lwndev-sdlc:documenting-qa
/lwndev-sdlc:executing-qa
/lwndev-sdlc:finalizing-workflow
```

## Workflow Chains

The skills form three workflow chains. The `reviewing-requirements` skill appears at multiple points — its mode is automatic based on context. Reconciliation steps are optional but recommended.

1. **Features**: `documenting-features` → `reviewing-requirements` → `creating-implementation-plans` → `documenting-qa` → `reviewing-requirements` *(reconciliation)* → `implementing-plan-phases` → *PR review* → `reviewing-requirements` *(reconciliation)* → `executing-qa` → `finalizing-workflow`
2. **Chores**: `documenting-chores` → `reviewing-requirements` → `documenting-qa` → `reviewing-requirements` *(reconciliation)* → `executing-chores` → *PR review* → `reviewing-requirements` *(reconciliation)* → `executing-qa` → `finalizing-workflow`
3. **Bugs**: `documenting-bugs` → `reviewing-requirements` → `documenting-qa` → `reviewing-requirements` *(reconciliation)* → `executing-bug-fixes` → *PR review* → `reviewing-requirements` *(reconciliation)* → `executing-qa` → `finalizing-workflow`
