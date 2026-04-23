# lwndev-sdlc

**Version:** 1.20.0 | **Released:** 2026-04-23

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
| **documenting-qa** | Builds an adversarial QA test plan from the user-facing summary, PR/diff, and capability report (intentionally decoupled from the requirements doc) |
| **executing-qa** | Executes adversarial QA against a feature branch, emitting a v2 results artifact with verdict, findings, and bidirectional reconciliation delta |
| **managing-work-items** | Centralizes issue tracker operations (GitHub Issues, Jira) — fetch, comment, PR-link generation — with automatic backend detection from the issue reference format |
| **orchestrating-workflows** | Drives a full SDLC workflow chain (feature, chore, bug) end-to-end by sequencing sub-skill invocations, persisting state across pause points, and isolating per-step context via subagent forking |
| **finalizing-workflow** | Merges the current PR, checks out main, fetches, and pulls — the terminal step in all workflow chains |

## Agents

| Agent | Model | Description |
|-------|-------|-------------|
| **qa-verifier** | Sonnet | Runs test suites, analyzes coverage, verifies code paths against acceptance criteria, and returns structured pass/fail verdicts. Used by `documenting-qa` and `executing-qa` skills via subagent delegation. |
| **qa-reconciliation-agent** | Sonnet | Reference spec for the bidirectional coverage-surplus / coverage-gap delta between a QA results artifact and its requirements document. Currently executed inline by `executing-qa` (FEAT-018 removed Ralph-style subagent loops); the description is authoritative for what the inline reconciliation produces. |

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
/lwndev-sdlc:managing-work-items
/lwndev-sdlc:orchestrating-workflows
/lwndev-sdlc:finalizing-workflow
```

## Workflow Chains

The skills form three workflow chains. The `orchestrating-workflows` skill drives any of these chains end-to-end from a single invocation, sequencing sub-skill calls, forking per-step subagents, and persisting state across pause points (plan approval, PR review). The `reviewing-requirements` skill appears at multiple points — its mode is automatic based on context — and reconciliation steps are optional but recommended. The `managing-work-items` skill is invoked inline (not as a numbered step) for issue-tracker operations.

1. **Features**: `documenting-features` → `reviewing-requirements` → `creating-implementation-plans` → `documenting-qa` → `reviewing-requirements` *(reconciliation)* → `implementing-plan-phases` → *PR review* → `reviewing-requirements` *(reconciliation)* → `executing-qa` → `finalizing-workflow`
2. **Chores**: `documenting-chores` → `reviewing-requirements` → `documenting-qa` → `reviewing-requirements` *(reconciliation)* → `executing-chores` → *PR review* → `reviewing-requirements` *(reconciliation)* → `executing-qa` → `finalizing-workflow`
3. **Bugs**: `documenting-bugs` → `reviewing-requirements` → `documenting-qa` → `reviewing-requirements` *(reconciliation)* → `executing-bug-fixes` → *PR review* → `reviewing-requirements` *(reconciliation)* → `executing-qa` → `finalizing-workflow`
