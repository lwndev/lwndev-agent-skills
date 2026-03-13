# Feature Requirements: Skill Allowed-Tools Declarations

## Overview

Add `allowed-tools` frontmatter to all 7 skill SKILL.md files so that Claude Code auto-allows the tools each skill needs, eliminating repetitive permission prompts during skill execution.

## Feature ID

`FEAT-003`

## GitHub Issue

[#19](https://github.com/lwndev/lwndev-agent-skills/issues/19)

## Priority

High - Every skill invocation currently prompts users for tool permissions, degrading the workflow experience

## User Story

As a skill user, I want tools to be auto-allowed when a skill is active so that I can execute skill workflows without being interrupted by permission prompts for every tool call.

## Functional Requirements

### FR-1: Documenting Skills Allowed-Tools

Add `allowed-tools` frontmatter to the 4 documenting/planning skills:

- `documenting-features`
- `documenting-chores`
- `documenting-bugs`
- `creating-implementation-plans`

These skills read existing files and write requirement documents. Required tools:

```yaml
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
```

### FR-2: Execution Skills Allowed-Tools

Add `allowed-tools` frontmatter to the 3 execution skills:

- `executing-chores`
- `executing-bug-fixes`
- `implementing-plan-phases`

These skills implement code changes, run commands, and create PRs. Required tools:

```yaml
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
```

### FR-3: Minimal Tool Lists

Each skill's `allowed-tools` must declare only the tools it actually uses. Do not add tools speculatively for future use.

### FR-4: Validation Compliance

All skills must pass `ai-skills-manager` validation after adding the field, including the `allowedToolsFormat` check.

## Non-Functional Requirements

### NFR-1: Consistency

All 7 skills must use the same frontmatter field name (`allowed-tools`) and format (YAML array of strings).

### NFR-2: Backwards Compatibility

Adding `allowed-tools` is additive. Skills must continue to work in environments that don't support the field.

## Dependencies

- `ai-skills-manager` v1.8.0+ (already installed at v1.8.1) — provides `allowed-tools` frontmatter validation

## Edge Cases

1. **Tool not in allowed list**: Claude Code falls back to prompting the user — no breakage
2. **Unrecognized tool name**: `ai-skills-manager` validation accepts any string, but Claude Code will ignore unknown names
3. **MCP tools**: Not needed by current skills; can be added later using `mcp__server__tool` pattern if needed

## Testing Requirements

### Unit Tests

- Each skill's test suite verifies `allowed-tools` is present in frontmatter
- Each skill's test suite verifies the tool list contains expected entries
- Documenting skills do NOT include `Bash` or `Agent` in their allowed-tools
- Execution skills DO include `Bash` and `Agent` in their allowed-tools

### Integration Tests

- All skills pass `ai-skills-manager` validation (existing `validate()` tests cover this)
- Build script produces valid `.skill` packages with the updated frontmatter

## Acceptance Criteria

- [x] All 7 SKILL.md files have `allowed-tools` in frontmatter
- [x] Documenting skills declare: Read, Write, Edit, Glob, Grep
- [x] Execution skills declare: Read, Write, Edit, Bash, Glob, Grep, Agent
- [x] All skills pass `asm validate`
- [x] Tests verify `allowed-tools` presence and correct tool lists
- [x] No existing tests broken
