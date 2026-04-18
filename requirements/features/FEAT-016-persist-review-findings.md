# Feature Requirements: Persist Reviewing-Requirements Findings in Workflow State

## Overview

Add findings persistence to the `orchestrating-workflows` skill so that reviewing-requirements results (severity counts, decision taken, and individual finding details) are recorded in the workflow state file after every reviewing-requirements step, regardless of the advance/pause decision. Currently, parsed severity counts and individual finding details are ephemeral — once the workflow advances past a review step, the only record of what was found is lost. This is especially acute on bug/chore chains where FEAT-015 auto-advances on warnings-only findings without surfacing them interactively.

## Feature ID
`FEAT-016`

## GitHub Issue
[#145](https://github.com/lwndev/lwndev-marketplace/issues/145)

## Priority
Medium - Findings from reviewing-requirements steps are lost after auto-advance, preventing post-hoc audit of what was found at each review checkpoint. Info items on auto-advance, warnings the user chose to skip, and post-fix residue all vanish without a trace.

## User Story

As a developer running SDLC workflows, I want the orchestrator to persist reviewing-requirements findings in the workflow state so that I can review what was found at each review step after the workflow has moved past it, without re-running the step.

## Motivation

The workflow state file (`.sdlc/workflows/{ID}.json`) records the decision (`status`, `pauseReason`, `artifact`) but not the findings themselves. Once the workflow advances past a reviewing-requirements step, the only way to see what was found is to re-run the step.

This is particularly relevant for:
- **Info items on auto-advance**: When all counts are zero or when bug/chore chains auto-advance past warnings/info (per FEAT-015/#139), findings vanish without a trace.
- **Warnings the user chose to skip**: When the user says "yes" to continue past warnings/info, there's no record of what they accepted.
- **Post-fix residue**: After the orchestrator applies auto-fixes and re-runs, the re-run findings (if any remain but are non-blocking) are also lost.

## Functional Requirements

### FR-1: Record Findings After Every Reviewing-Requirements Step

After the orchestrator parses the reviewing-requirements subagent's return text (the summary line `Found **N errors**, **N warnings**, **N info**` or "No issues found"), record the findings in the workflow state file **before** making the advance/pause decision. This applies to all three modes (standard, test-plan, code-review) and all chain types (feature, chore, bug).

The recording must happen at every reviewing-requirements step in the chain tables (one-based step numbers; zero-based `stepIndex` values are one less):
- Feature chain: steps 2, 6, 6+N+3 (zero-based indices 1, 5, 5+N+2)
- Chore chain: steps 2, 4, 7 (zero-based indices 1, 3, 6)
- Bug chain: steps 2, 4, 7 (zero-based indices 1, 3, 6)

Skipped steps (CHORE-031 low-complexity skip for steps 2 and 4 on chore/bug chains) do not produce findings and therefore have no `findings` entry.

### FR-2: Findings Schema

Each findings record is stored on the step entry in the `steps` array. Add a `findings` field to reviewing-requirements step entries with the following structure:

```json
{
  "findings": {
    "errors": "<int>",
    "warnings": "<int>",
    "info": "<int>",
    "decision": "<string>",
    "summary": "<string>",
    "details": [
      {
        "id": "<string>",
        "severity": "<string>",
        "category": "<string>",
        "description": "<string>"
      }
    ]
  }
}
```

Fields:
- `errors` — Count of error-severity findings (integer, >= 0)
- `warnings` — Count of warning-severity findings (integer, >= 0)
- `info` — Count of info-severity findings (integer, >= 0)
- `decision` — The action the orchestrator took after parsing findings. One of:
  - `"advanced"` — Zero findings; state advanced automatically
  - `"auto-advanced"` — Warnings/info only; auto-advanced by FR-1 gate (FEAT-015 bug/chore <= medium)
  - `"user-advanced"` — Warnings/info only; user prompted and confirmed continuation
  - `"auto-fixed"` — Errors present; user chose "Apply fixes" (records user intent at the decision point; the re-run outcome is captured separately in `rerunFindings.decision`)
  - `"paused"` — User declined to continue (warnings prompt), or user chose "Pause for manual resolution" on errors
- `summary` — The raw summary line from the subagent return text, stored verbatim including the trailing `in <filename>` suffix if present (e.g., `"Found **2 errors**, **4 warnings**, **1 info** in FEAT-016-persist-review-findings.md"` or `"No issues found"`). Preserves the exact text for later display; consumers can strip the filename at query time.
- `details` — Array of individual finding objects. **Required when `decision` is `"auto-advanced"`**; omitted for all other decisions (where the user either sees the findings interactively or there are none to record). Each object contains:
  - `id` — The finding identifier from the subagent output (e.g., `"W1"`, `"I3"`)
  - `severity` — One of `"error"`, `"warning"`, `"info"`
  - `category` — The check category that produced the finding (e.g., `"Codebase References"`, `"Internal Consistency"`, `"Gaps"`, `"Cross-References"`, `"Documentation Citations"`)
  - `description` — The finding description, trimmed to a single line. Preserves enough context to understand the issue without re-running the review.

### FR-3: Record Re-Run Findings

When the orchestrator applies auto-fixes and re-runs reviewing-requirements (the "Applying Auto-Fixes" path), the re-run also produces findings. Record the re-run findings as a separate entry:

Add a `rerunFindings` field alongside `findings` on the same step entry:

```json
{
  "findings": { "..." : "..." },
  "rerunFindings": {
    "errors": "<int>",
    "warnings": "<int>",
    "info": "<int>",
    "decision": "<string>",
    "summary": "<string>"
  }
}
```

The `rerunFindings` field uses the same schema as `findings`. It is only present when an auto-fix + re-run occurred. The `decision` field on the re-run reflects the re-run outcome (`"advanced"`, `"auto-advanced"`, or `"paused"`). The `details` field follows the same conditional rule: required when `decision` is `"auto-advanced"`, omitted otherwise.

### FR-4: `record-findings` Subcommand

Add a `record-findings` subcommand to `workflow-state.sh`:

```
workflow-state.sh record-findings <ID> <stepIndex> <errors> <warnings> <info> <decision> <summary> [--rerun] [--details-file <path>]
```

Arguments:
- `ID` — Workflow ID (e.g., `FEAT-016`)
- `stepIndex` — Zero-based step index in the `steps` array
- `errors` — Error count (integer)
- `warnings` — Warning count (integer)
- `info` — Info count (integer)
- `decision` — One of: `advanced`, `auto-advanced`, `user-advanced`, `auto-fixed`, `paused`
- `summary` — The raw summary line (quoted string; must be passed as a single shell-quoted token)
- `--rerun` — Optional flag. When present, writes to `rerunFindings` instead of `findings`.
- `--details-file <path>` — Optional. Path to a JSON file containing the `details` array. **Required when `decision` is `auto-advanced`**; ignored for other decisions. The file must contain a JSON array of finding objects matching the `details` schema (see FR-2). The subcommand reads the file, validates it is a JSON array, and merges it into the findings object. The caller is responsible for writing the temp file and cleaning it up after the call.

The subcommand writes the findings object to `steps[stepIndex].findings` (or `steps[stepIndex].rerunFindings` with `--rerun`) using `jq` and persists the state file. When `--details-file` is provided and `decision` is `auto-advanced`, the `details` array from the file is included in the written object. When `--details-file` is omitted or `decision` is not `auto-advanced`, the `details` field is not written.

### FR-5: Orchestrator Integration Points

Update the Reviewing-Requirements Findings Handling section in the orchestrating-workflows SKILL.md to call `record-findings` at each decision point:

1. **Zero findings (auto-advance)**: Call `record-findings {ID} {stepIndex} 0 0 0 advanced "No issues found"` before calling `advance`. Note: if the subagent returns `Found **0 errors**, **0 warnings**, **0 info**` (parseable as zeros), normalize the summary to `"No issues found"` — both forms mean zero findings, but `"No issues found"` is the canonical summary.
2. **Warnings/info only, auto-advanced (FEAT-015 gate)**: Parse the individual findings from the subagent's return text (each `[W1]`, `[I1]`, etc. entry), build a JSON array of finding objects matching the `details` schema, write it to a temp file, and call `record-findings {ID} {stepIndex} 0 {W} {I} auto-advanced "{summary}" --details-file {tmp-path}` before calling `advance`. Clean up the temp file after the call. See FR-7 for the parsing specification.
3. **Warnings/info only, user prompted and confirmed**: Call `record-findings {ID} {stepIndex} 0 {W} {I} user-advanced "{summary}"` before calling `advance`.
4. **Warnings/info only, user declined**: Call `record-findings {ID} {stepIndex} 0 {W} {I} paused "{summary}"` before calling `pause`.
5. **Errors present, user chose "Apply fixes"**: Call `record-findings {ID} {stepIndex} {E} {W} {I} auto-fixed "{summary}"` at the decision point (before applying fixes — `auto-fixed` records user intent, not re-run outcome). After the re-run, call `record-findings {ID} {stepIndex} {E2} {W2} {I2} {rerun-decision} "{rerun-summary}" --rerun`. The `rerunFindings.decision` captures the re-run outcome: `"advanced"` if zero errors after fix, `"auto-advanced"` if warnings/info only on a bug/chore chain with `complexity <= medium` (requires `--details-file` per FR-2), `"paused"` if errors remain.
6. **Errors present, user chose "Pause"**: Call `record-findings {ID} {stepIndex} {E} {W} {I} paused "{summary}"` before calling `pause`.

### FR-6: Queryable via `status` Subcommand

The existing `status` subcommand (which returns the full state JSON) already exposes the `steps` array. No additional query subcommand is needed — consumers can use `jq` to extract findings:

```bash
# Get findings for step 2 (standard review) — zero-based index 1
jq '.steps[1].findings' ".sdlc/workflows/FEAT-016.json"

# List all reviewing-requirements findings across the workflow
jq '[.steps[] | select(.skill == "reviewing-requirements") | {name, findings, rerunFindings}]' ".sdlc/workflows/FEAT-016.json"

# List auto-advanced finding details (warnings/info that bypassed user review)
jq '[.steps[] | select(.findings.decision == "auto-advanced") | .findings.details[]]' ".sdlc/workflows/FEAT-016.json"
```

### FR-7: Parsing Finding Details from Subagent Output

When the decision is `auto-advanced`, the orchestrator must extract individual findings from the subagent's return text before calling `record-findings`. The reviewing-requirements skill outputs findings in this format:

```
**[W1] Category — Description**
Additional context lines...

**[I1] Category — Description**
Additional context lines...
```

The orchestrator parses these into the `details` array by:

1. **Scanning** the subagent return text for lines matching the pattern `**[{severity}{number}] {category} — {description}**` (or the variant without bold markers: `[{severity}{number}] {category} — {description}`). The separator between category and description is an em dash (`—`, U+2014); the parser should also accept an ASCII double-hyphen (`--`) as a fallback. The severity prefix maps as: `E` → `"error"`, `W` → `"warning"`, `I` → `"info"`.
2. **Extracting** for each match:
   - `id` — The severity+number token (e.g., `"W1"`, `"I3"`)
   - `severity` — Mapped from the prefix letter
   - `category` — The text between `]` and `—` (trimmed)
   - `description` — The text after `—` to end of line (trimmed, stripped of trailing bold markers)
3. **Writing** the resulting JSON array to a temp file at `/tmp/findings-{ID}-{stepIndex}.json`
4. **Passing** the path via `--details-file` to `record-findings`
5. **Cleaning up** the temp file after `record-findings` returns

If no individual findings can be parsed from the subagent text (despite non-zero warning/info counts), write an empty array `[]` and log: `[warn] Could not parse individual findings from reviewing-requirements output — recording counts only.`

## Non-Functional Requirements

### NFR-1: Backwards Compatibility

The `findings` and `rerunFindings` fields are additive. Existing state files without these fields remain valid. The `status` subcommand does not require these fields to be present. No migration is needed for existing workflows.

### NFR-2: No Impact on Decision Flow

The findings recording happens independently of the advance/pause decision. The existing Decision Flow logic (zero findings → advance, warnings-only → gate, errors → prompt) is unchanged. `record-findings` is called at each decision point but does not influence the decision itself.

### NFR-3: Recording Before Decision Execution

`record-findings` must be called **before** `advance` or `pause` at every decision point. This ensures that if the `advance`/`pause` call fails or the process crashes, the findings are still persisted.

### NFR-4: Scope of Changes

Changes are limited to:
1. `workflow-state.sh` — Add the `record-findings` subcommand and its usage entry
2. `orchestrating-workflows/SKILL.md` — Add `record-findings` calls at each decision point in the Reviewing-Requirements Findings Handling section
3. No changes to the `reviewing-requirements` skill itself
4. No changes to any other subcommand's behavior

## Edge Cases

1. **Subagent returns no parseable summary line**: If the subagent returns text that does not contain the `Found **N errors**...` pattern or "No issues found", record `errors=0, warnings=0, info=0, decision="advanced", summary="(unparseable)"`. Log a warning: `[warn] Could not parse reviewing-requirements summary — recording as zero findings.`
2. **Step skipped by CHORE-031**: Skipped steps call `advance` without spawning a reviewing-requirements fork. No `findings` field is written. The `findings` field being absent signals "step was skipped". The CHORE-031 skip path requires no modification — no `record-findings` call is inserted on the skip path.
3. **Re-run not triggered**: When the initial findings have zero errors, or the user chooses "Pause" on errors, no re-run occurs. The `rerunFindings` field is absent, signaling "no re-run happened".
4. **Summary line contains shell-special characters**: The `summary` argument to `record-findings` must be quoted. The subcommand handles embedded quotes and special characters safely via `jq --arg`.
5. **Concurrent state file writes**: The `record-findings` and `advance`/`pause` calls are sequential (FR-5 calls `record-findings` before `advance`/`pause`), so no concurrent write conflict occurs within a single workflow.
6. **Details parsing produces fewer items than severity counts**: If the parser extracts 2 findings but the summary line reports 3 warnings, record what was parsed. The counts in `errors`/`warnings`/`info` come from the summary line (authoritative); the `details` array is best-effort. A mismatch is not an error.
7. **Details file does not exist or is not valid JSON**: If `--details-file` points to a missing file or the file does not contain a valid JSON array, `record-findings` writes the findings object without a `details` field and logs: `[warn] Could not read details file — recording counts only.`

## Dependencies

- `jq` — Already a dependency of `workflow-state.sh`
- FEAT-015 / #139 — The auto-advance gate for bug/chore chains (FR-1 gate, `auto-advanced` decision value) depends on the FEAT-015 behavior being in place

## Testing Requirements

### Unit Tests
- `record-findings` subcommand: verify it writes the correct JSON structure to the state file
- `record-findings --rerun`: verify it writes to `rerunFindings` without overwriting `findings`
- `record-findings` with shell-special characters in summary: verify safe handling
- `record-findings --details-file`: verify the `details` array is included when `decision` is `auto-advanced`
- `record-findings --details-file` with non-`auto-advanced` decision: verify `details` is not written
- `record-findings --details-file` with invalid JSON file: verify graceful error handling
- `record-findings` with out-of-bounds `stepIndex`: verify graceful error handling
- `status` subcommand: verify it returns findings data (including `details`) when present and works when absent

### Manual Testing
- Run a bug or chore workflow where reviewing-requirements returns zero findings. Verify `findings` field with `decision: "advanced"` appears on the step entry.
- Run a bug or chore workflow (complexity <= medium) where reviewing-requirements returns warnings-only. Verify `findings` field with `decision: "auto-advanced"` and a populated `details` array.
- Run a feature workflow where reviewing-requirements returns warnings-only and the user confirms. Verify `findings` field with `decision: "user-advanced"`.
- Run a workflow where reviewing-requirements returns errors, user applies fixes, and re-run succeeds. Verify both `findings` (with `decision: "auto-fixed"`) and `rerunFindings` (with `decision: "advanced"`).
- Run a workflow where reviewing-requirements returns errors, user applies fixes, and re-run still has errors. Verify `findings` (with `decision: "auto-fixed"`) and `rerunFindings` (with `decision: "paused"`).
- Run a workflow where reviewing-requirements returns errors and user pauses. Verify `findings` field with `decision: "paused"`.
- Inspect a completed workflow state file and confirm all reviewing-requirements steps have findings recorded.

## Acceptance Criteria

- [ ] After every non-skipped reviewing-requirements step, the workflow state file contains a `findings` object on the step entry with `errors`, `warnings`, `info`, `decision`, and `summary` fields
- [ ] Auto-advanced steps (FEAT-015 warnings-only gate) include a `findings` record with a `details` array containing each individual finding's `id`, `severity`, `category`, and `description`
- [ ] Non-auto-advanced steps (zero findings, user-advanced, auto-fixed, paused) include a `findings` record without a `details` array
- [ ] When auto-fixes are applied and a re-run occurs, both `findings` and `rerunFindings` are present on the step entry
- [ ] Skipped steps (CHORE-031 low-complexity) have no `findings` field, distinguishing "skipped" from "zero findings"
- [ ] The `record-findings` subcommand in `workflow-state.sh` correctly persists findings with all decision variants
- [ ] Existing workflow state files without `findings` fields remain valid (no migration needed)
- [ ] The Decision Flow logic is unchanged — `record-findings` is additive and does not influence advance/pause decisions
