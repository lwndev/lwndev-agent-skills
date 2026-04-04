# Jira Templates

Templates for Jira issue interactions in [Atlassian Document Format (ADF)](https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/) JSON format. These templates are used by the Rovo MCP backend path (`addCommentToJiraIssue`); the `acli` backend accepts markdown and handles ADF conversion internally.

> **ADF Reference**: Every ADF document is a JSON object with `version: 1`, `type: "doc"`, and a `content` array of block nodes (`paragraph`, `heading`, `bulletList`, `orderedList`, `codeBlock`, `table`, `panel`, `rule`). Text nodes carry formatting via a `marks` array (`strong`, `em`, `code`, `link`). See the [ADF specification](https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/) for full details.

## Table of Contents

- [Comment Templates](#comment-templates)
  - [phase-start](#phase-start)
  - [phase-completion](#phase-completion)
  - [work-start](#work-start)
  - [work-complete](#work-complete)
  - [bug-start](#bug-start)
  - [bug-complete](#bug-complete)
- [Rendering Notes](#rendering-notes)

---

## Comment Templates

### phase-start

**Context variables**: `phase` (number), `name` (phase name), `steps` (list), `deliverables` (list), `workItemId` (FEAT-XXX)

```json
{
  "version": 1,
  "type": "doc",
  "content": [
    {
      "type": "panel",
      "attrs": { "panelType": "info" },
      "content": [
        {
          "type": "paragraph",
          "content": [
            { "type": "text", "text": "Phase In Progress", "marks": [{ "type": "strong" }] }
          ]
        }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 3 },
      "content": [
        { "type": "text", "text": "Starting Phase {phase}: {name}" }
      ]
    },
    {
      "type": "paragraph",
      "content": [
        { "type": "text", "text": "Work item: " },
        { "type": "text", "text": "{workItemId}", "marks": [{ "type": "strong" }] }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 4 },
      "content": [
        { "type": "text", "text": "Implementation Steps" }
      ]
    },
    {
      "type": "orderedList",
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{steps[0]}" }
              ]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{steps[1]}" }
              ]
            }
          ]
        }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 4 },
      "content": [
        { "type": "text", "text": "Expected Deliverables" }
      ]
    },
    {
      "type": "bulletList",
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{deliverables[0]}" }
              ]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{deliverables[1]}" }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

**Rendering notes**: The `orderedList` and `bulletList` nodes above show two items each as a structural example. When rendering, dynamically generate one `listItem` node per entry in the `steps` and `deliverables` context arrays. Each `listItem` must contain a `paragraph` node wrapping the text.

### phase-completion

**Context variables**: `phase` (number), `name` (phase name), `deliverables` (verified list), `commitSha` (short SHA), `workItemId` (FEAT-XXX)

```json
{
  "version": 1,
  "type": "doc",
  "content": [
    {
      "type": "panel",
      "attrs": { "panelType": "success" },
      "content": [
        {
          "type": "paragraph",
          "content": [
            { "type": "text", "text": "Phase Complete", "marks": [{ "type": "strong" }] }
          ]
        }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 3 },
      "content": [
        { "type": "text", "text": "Completed Phase {phase}: {name}" }
      ]
    },
    {
      "type": "paragraph",
      "content": [
        { "type": "text", "text": "Work item: " },
        { "type": "text", "text": "{workItemId}", "marks": [{ "type": "strong" }] }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 4 },
      "content": [
        { "type": "text", "text": "Deliverables Verified" }
      ]
    },
    {
      "type": "bulletList",
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{deliverables[0]}" }
              ]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{deliverables[1]}" }
              ]
            }
          ]
        }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 4 },
      "content": [
        { "type": "text", "text": "Verification" }
      ]
    },
    {
      "type": "bulletList",
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "Tests passing" }
              ]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "Build successful" }
              ]
            }
          ]
        }
      ]
    },
    {
      "type": "paragraph",
      "content": [
        { "type": "text", "text": "Commit: " },
        { "type": "text", "text": "{commitSha}", "marks": [{ "type": "code" }] }
      ]
    }
  ]
}
```

**Rendering notes**: Dynamically generate one `listItem` per entry in the `deliverables` context array. Each deliverable should include a checkmark or verified indicator in its text.

### work-start

**Context variables**: `choreId` (CHORE-XXX), `criteria` (acceptance criteria list), `branch` (branch name)

```json
{
  "version": 1,
  "type": "doc",
  "content": [
    {
      "type": "panel",
      "attrs": { "panelType": "info" },
      "content": [
        {
          "type": "paragraph",
          "content": [
            { "type": "text", "text": "Work In Progress", "marks": [{ "type": "strong" }] }
          ]
        }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 3 },
      "content": [
        { "type": "text", "text": "Starting work on {choreId}" }
      ]
    },
    {
      "type": "paragraph",
      "content": [
        { "type": "text", "text": "Branch: " },
        { "type": "text", "text": "{branch}", "marks": [{ "type": "code" }] }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 4 },
      "content": [
        { "type": "text", "text": "Acceptance Criteria" }
      ]
    },
    {
      "type": "bulletList",
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{criteria[0]}" }
              ]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{criteria[1]}" }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

**Rendering notes**: Dynamically generate one `listItem` per entry in the `criteria` context array.

### work-complete

**Context variables**: `choreId` (CHORE-XXX), `prNumber` (PR number), `criteria` (verified criteria list)

```json
{
  "version": 1,
  "type": "doc",
  "content": [
    {
      "type": "panel",
      "attrs": { "panelType": "success" },
      "content": [
        {
          "type": "paragraph",
          "content": [
            { "type": "text", "text": "Work Complete", "marks": [{ "type": "strong" }] }
          ]
        }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 3 },
      "content": [
        { "type": "text", "text": "Completed {choreId}" }
      ]
    },
    {
      "type": "paragraph",
      "content": [
        { "type": "text", "text": "Pull Request: " },
        { "type": "text", "text": "#{prNumber}", "marks": [{ "type": "strong" }] }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 4 },
      "content": [
        { "type": "text", "text": "Acceptance Criteria Verified" }
      ]
    },
    {
      "type": "bulletList",
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{criteria[0]}" }
              ]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{criteria[1]}" }
              ]
            }
          ]
        }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 4 },
      "content": [
        { "type": "text", "text": "Verification" }
      ]
    },
    {
      "type": "bulletList",
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "Tests passing" }
              ]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "Build successful" }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

**Rendering notes**: Dynamically generate one `listItem` per entry in the `criteria` context array. Each criterion should include a verified indicator in its text.

### bug-start

**Context variables**: `bugId` (BUG-XXX), `severity` (level), `rootCauses` (RC-N list), `criteria` (acceptance criteria list), `branch` (branch name)

```json
{
  "version": 1,
  "type": "doc",
  "content": [
    {
      "type": "panel",
      "attrs": { "panelType": "warning" },
      "content": [
        {
          "type": "paragraph",
          "content": [
            { "type": "text", "text": "Bug Fix In Progress", "marks": [{ "type": "strong" }] }
          ]
        }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 3 },
      "content": [
        { "type": "text", "text": "Starting work on {bugId}" }
      ]
    },
    {
      "type": "paragraph",
      "content": [
        { "type": "text", "text": "Severity: " },
        { "type": "text", "text": "{severity}", "marks": [{ "type": "strong" }] }
      ]
    },
    {
      "type": "paragraph",
      "content": [
        { "type": "text", "text": "Branch: " },
        { "type": "text", "text": "{branch}", "marks": [{ "type": "code" }] }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 4 },
      "content": [
        { "type": "text", "text": "Root Causes to Address" }
      ]
    },
    {
      "type": "orderedList",
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "RC-1", "marks": [{ "type": "strong" }] },
                { "type": "text", "text": ": {rootCauses[0]}" }
              ]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "RC-2", "marks": [{ "type": "strong" }] },
                { "type": "text", "text": ": {rootCauses[1]}" }
              ]
            }
          ]
        }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 4 },
      "content": [
        { "type": "text", "text": "Acceptance Criteria" }
      ]
    },
    {
      "type": "bulletList",
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{criteria[0]}" }
              ]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{criteria[1]}" }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

**Rendering notes**: Dynamically generate one `listItem` per entry in the `rootCauses` and `criteria` context arrays. Each root cause `listItem` must preserve the `RC-N` tag in bold, followed by the description. The `RC-N` numbering must match the root cause numbering from the bug document for traceability.

### bug-complete

**Context variables**: `bugId` (BUG-XXX), `prNumber` (PR number), `rootCauseResolutions` (RC-N resolution table), `verificationResults` (list)

```json
{
  "version": 1,
  "type": "doc",
  "content": [
    {
      "type": "panel",
      "attrs": { "panelType": "success" },
      "content": [
        {
          "type": "paragraph",
          "content": [
            { "type": "text", "text": "Bug Fix Complete", "marks": [{ "type": "strong" }] }
          ]
        }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 3 },
      "content": [
        { "type": "text", "text": "Completed {bugId}" }
      ]
    },
    {
      "type": "paragraph",
      "content": [
        { "type": "text", "text": "Pull Request: " },
        { "type": "text", "text": "#{prNumber}", "marks": [{ "type": "strong" }] }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 4 },
      "content": [
        { "type": "text", "text": "Root Cause Resolution" }
      ]
    },
    {
      "type": "bulletList",
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "RC-1", "marks": [{ "type": "strong" }] },
                { "type": "text", "text": ": {rootCauseResolutions[0].cause} — " },
                { "type": "text", "text": "{rootCauseResolutions[0].resolution}", "marks": [{ "type": "em" }] }
              ]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "RC-2", "marks": [{ "type": "strong" }] },
                { "type": "text", "text": ": {rootCauseResolutions[1].cause} — " },
                { "type": "text", "text": "{rootCauseResolutions[1].resolution}", "marks": [{ "type": "em" }] }
              ]
            }
          ]
        }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 4 },
      "content": [
        { "type": "text", "text": "Verification" }
      ]
    },
    {
      "type": "bulletList",
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "All root causes addressed" }
              ]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "Reproduction steps verified — bug no longer occurs" }
              ]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{verificationResults[0]}" }
              ]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "text", "text": "{verificationResults[1]}" }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

**Rendering notes**: Dynamically generate one `listItem` per entry in the `rootCauseResolutions` context array. Each root cause resolution `listItem` must preserve the `RC-N` tag in bold for traceability, followed by the cause description and the resolution in italic. Generate additional `listItem` nodes in the verification section for each entry in the `verificationResults` context array.

---

## Rendering Notes

### Variable Substitution

When rendering ADF templates, replace placeholders with actual values from the `--context` JSON:

- **Scalar variables** (`{phase}`, `{name}`, `{commitSha}`, etc.): Direct string substitution in `text` fields.
- **List variables** (`{steps[N]}`, `{deliverables[N]}`, `{criteria[N]}`, `{rootCauses[N]}`): Generate one `listItem` node per entry in the context array. The `[N]` index notation in the template indicates that the list nodes should be dynamically expanded.
- **Object list variables** (`{rootCauseResolutions[N].cause}`, `{rootCauseResolutions[N].resolution}`): Generate one `listItem` node per entry, with multiple text nodes per item accessing different object properties.

### ADF Validity Requirements

All rendered ADF must conform to these structural rules:

- Top-level object: `{ "version": 1, "type": "doc", "content": [...] }`
- `content` array contains only block nodes (`paragraph`, `heading`, `bulletList`, `orderedList`, `panel`, `codeBlock`, `rule`, `table`)
- `bulletList` and `orderedList` contain only `listItem` children
- `listItem` nodes must contain at least one block node (typically `paragraph`)
- `heading` nodes require `attrs.level` (1-6)
- `panel` nodes require `attrs.panelType` (`info`, `note`, `warning`, `success`, `error`)
- Text formatting uses `marks` array on text nodes: `strong` (bold), `em` (italic), `code` (monospace), `link` (with `attrs.href`)
- Invalid ADF will cause Jira API rejections -- always verify the structure before posting

### Work Item ID Traceability

All templates include the work item ID for traceability:

- **Phase templates**: `{workItemId}` renders as `FEAT-XXX`
- **Work templates**: `{choreId}` renders as `CHORE-XXX`
- **Bug templates**: `{bugId}` renders as `BUG-XXX`, plus `RC-N` tags for root cause traceability
