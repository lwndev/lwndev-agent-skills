---
name: my-awesome-skill
description: A very awesome skill that makes awesome things happen
# allowed-tools:
#   - Bash
#   - Read
#   - Write
#   - Edit
#   - Glob
#   - Grep
---

# my-awesome-skill

## Overview

TODO: Describe what this skill does and when Claude should use it.

## Usage

TODO: Explain how to invoke this skill and any required context.

## Examples

TODO: Provide examples of prompts that trigger this skill.

### Example 1

```
User: [example prompt]
Claude: [expected behavior]
```

## Implementation Notes

TODO: Add any implementation details, edge cases, or important considerations.

<!--
================================================================================
SKILL DEVELOPMENT GUIDANCE
================================================================================

This file defines a Claude Code skill. Skills are markdown files with YAML
frontmatter that teach Claude how to perform specific tasks.

FRONTMATTER FIELDS:
- name: (required) Unique identifier for this skill
- description: (required) Brief description shown in skill listings. This is the
  PRIMARY triggering mechanism - include all "when to use" information here.
- allowed-tools: (optional) List of tools this skill can use
- license: (optional) License for the skill (e.g., "MIT", "Apache-2.0")

BEST PRACTICES:
1. Keep skills focused on a single task or related set of tasks
2. Put ALL trigger conditions in the description field, not the body
3. Provide clear examples of expected behavior
4. Include edge cases and error handling guidance
5. Keep the total skill file under 500 lines for optimal performance

DESCRIPTION PATTERNS:
Use these patterns in your description for reliable triggering:
- "Use when the user wants to..."
- "Apply this skill for..."
- "This skill should be used when..."

ALLOWED TOOLS:
Common tools you can specify in allowed-tools:
- Bash: Execute shell commands
- Read: Read file contents
- Write: Write/create files
- Edit: Edit existing files
- Glob: Find files by pattern
- Grep: Search file contents
- WebFetch: Fetch web content
- WebSearch: Search the web

If no allowed-tools are specified, the skill inherits default tool access.

SCRIPTS DIRECTORY:
The scripts/ subdirectory can contain helper scripts that your skill
references. These are executed via the Bash tool when needed.

For more information, see: https://docs.anthropic.com/en/docs/claude-code
================================================================================
-->
