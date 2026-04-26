# QA Return Contract

Canonical spec for the `executing-qa` return surface. Producers (Phase-2 scripts), the workflow-state persister (`record-findings --type qa`), and the orchestrator parser (`parse-qa-return.sh`) all cite this document as the single source of truth.

---

## Artifact Schema

The results artifact is written to `qa/test-results/QA-results-{ID}.md`.

### Frontmatter Fields

| Field | Value |
|-------|-------|
| `id` | Full requirement ID (e.g., `FEAT-030`) |
| `version` | `2` (integer; `1` is the legacy closed-loop format and is rejected) |
| `timestamp` | ISO-8601 datetime string |
| `verdict` | One of `PASS`, `ISSUES-FOUND`, `ERROR`, `EXPLORATORY-ONLY` |
| `persona` | `qa` |

### Required Sections

All artifacts must include the following top-level sections in this order:

1. `## Summary`
2. `## Capability Report`
3. `## Execution Results` (required for `PASS`, `ISSUES-FOUND`, `ERROR`; optional for `EXPLORATORY-ONLY`)
4. `## Scenarios Run`
5. `## Findings`
6. `## Reconciliation Delta`
7. `## Exploratory Mode` (required only when verdict is `EXPLORATORY-ONLY`)

### Per-Verdict Structural Rules

**`PASS`**
- `## Execution Results` must contain `Failed: 0`.
- `## Findings` must be empty (no findings entries).

**`ISSUES-FOUND`**
- `## Findings` must list at least one failing test name (not a placeholder).
- Failing test names are drawn from the runner's actual output — never self-reported.

**`ERROR`**
- A stack trace or runner crash output must appear in `## Execution Results` or `## Findings`.
- Cause: runner could not compile/parse the written tests, or `git diff main...HEAD` was empty.

**`EXPLORATORY-ONLY`**
- `## Exploratory Mode` must include a `Reason:` line explaining the fallback (e.g., `Reason: No supported test framework detected.`).
- Counts in the final-message line are `Passed: 0 | Failed: 0 | Errored: 0`.

---

## Final-Message Line

The **final line** of every `executing-qa` skill response must be exactly:

```
Verdict: <PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY> | Passed: <int> | Failed: <int> | Errored: <int>
```

Examples:

```
Verdict: PASS | Passed: 12 | Failed: 0 | Errored: 0
Verdict: ISSUES-FOUND | Passed: 9 | Failed: 3 | Errored: 0
Verdict: ERROR | Passed: 0 | Failed: 0 | Errored: 1
Verdict: EXPLORATORY-ONLY | Passed: 0 | Failed: 0 | Errored: 0
```

Rules:

- The verdict token must be uppercase and match the `verdict` frontmatter field exactly.
- Integer counts are non-negative. No leading zeros beyond a bare `0`.
- No extra whitespace before or after `|` separators beyond the single space shown.
- For `EXPLORATORY-ONLY`, all three counts are `0`.

### Canonical Regex

The orchestrator (`parse-qa-return.sh`) matches the final-message line with this regex:

```
^Verdict: (PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY) \| Passed: ([0-9]+) \| Failed: ([0-9]+) \| Errored: ([0-9]+)$
```

No extra whitespace is tolerated. The regex is the tightest reasonable form and is the authoritative match pattern. Any deviation causes a contract-mismatch error on the orchestrator side.

---

## Workflow-State Findings JSON

After `executing-qa` returns, the orchestrator calls `parse-qa-return.sh` to extract findings and persists them via `workflow-state.sh record-findings --type qa`. The findings JSON shape is:

```json
{
  "verdict": "<PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY>",
  "passed": <int>,
  "failed": <int>,
  "errored": <int>,
  "summary": "<single-line summary derived from artifact ## Summary section, plus artifact path pointer>"
}
```

Field rules:

- `verdict`: uppercase string matching the `verdict` frontmatter field and the final-message line.
- `passed`, `failed`, `errored`: non-negative integers parsed from the final-message line.
- `summary`: one-line string. Derived from the first non-empty paragraph of the artifact's `## Summary` section, followed by a path pointer ` (artifact: qa/test-results/QA-results-{ID}.md)`.

### Storage Location

The findings block is persisted on the QA step entry in the workflow state file:

```
steps[<index>].findings
```

Where `<index>` is the zero-based index of the executing-qa step in the workflow's `steps` array. The parent-key path is resolved by the orchestrator from the step's `skill` field (`executing-qa`) before calling `record-findings`.

Workflow state files that predate FEAT-030 (lacking a `findings` block on QA steps) are loaded without error; the `record-findings --type qa` call adds the block at write time.
