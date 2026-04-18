# Implementation Plan: Persist Reviewing-Requirements Findings in Workflow State

## Overview

Add findings persistence to the `orchestrating-workflows` skill so that reviewing-requirements results are durably recorded in the workflow state file at every decision point. Currently, parsed severity counts and individual finding details are ephemeral — once the workflow advances past a review step, the only record of what was found is lost. This is especially acute on bug/chore chains where FEAT-015 auto-advances on warnings-only findings without surfacing them interactively.

The change is scoped to two artifacts: a new `record-findings` subcommand in `workflow-state.sh` and prose additions to the "Reviewing-Requirements Findings Handling" section of `orchestrating-workflows/SKILL.md`. No sub-skills are modified, no new state schema fields are introduced beyond `findings`/`rerunFindings` on step entries, and no migration is required for existing workflows.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-016 | [#145](https://github.com/lwndev/lwndev-marketplace/issues/145) | [FEAT-016-persist-review-findings.md](../features/FEAT-016-persist-review-findings.md) | Medium | Medium | Pending |

## Recommended Build Sequence

The implementation has a natural dependency order: `workflow-state.sh` must expose the `record-findings` subcommand before the `SKILL.md` prose can call it. Phase 1 delivers the subcommand and its unit tests in isolation; Phase 2 adds the orchestrator integration calls.

---

### Phase 1: `record-findings` Subcommand in `workflow-state.sh`
**Feature:** [FEAT-016](../features/FEAT-016-persist-review-findings.md) | [#145](https://github.com/lwndev/lwndev-marketplace/issues/145)
**Status:** ✅ Complete

#### Rationale

- The `workflow-state.sh` script is independently testable via the existing vitest harness in `scripts/__tests__/workflow-state.test.ts`. Implementing `record-findings` here first means Phase 2's prose changes can be validated with a working subcommand already on disk.
- All JSON serialization decisions (numeric count fields, conditional `details` inclusion, `rerunFindings` placement alongside `findings`) are encoded in the shell script once, keeping the SKILL.md prose concise.
- The subcommand's out-of-bounds guard, shell-special-character safety, and `--details-file` validation are mechanical invariants that belong in the script layer, not in orchestrator prose.
- This phase is independently mergeable — the subcommand can sit in `workflow-state.sh` with no callers until Phase 2 adds the call sites.

#### Implementation Steps

1. **Add `record-findings` to the `usage()` function** (between the `clear-gate` entry and the closing `exit 1`) with the exact signature from FR-4:
   ```
   record-findings <ID> <stepIndex> <errors> <warnings> <info> <decision> <summary> [--rerun] [--details-file <path>]
   ```
   Follow the existing multi-line echo style used by other long-form entries (e.g., `record-model-selection`, `classify-init`).

2. **Implement `cmd_record_findings()`** as a new function in the script, placed near `cmd_record_model_selection()` for proximity with other step-mutation helpers. The function must:
   - Accept positional args: `id`, `step_index`, `errors`, `warnings`, `info`, `decision`, `summary`
   - Parse the optional `--rerun` flag and `--details-file <path>` from the remaining `$@`
   - Validate `step_index` is a non-negative integer (reuse the guard pattern from `cmd_record_model_selection`)
   - Validate `errors`, `warnings`, `info` are non-negative integers
   - Validate `decision` is one of: `advanced`, `auto-advanced`, `user-advanced`, `auto-fixed`, `paused`
   - Call `validate_state_file` to load the state file path
   - Perform a bounds check: if `step_index >= length(.steps)`, emit to stderr `Error: stepIndex {N} out of bounds for workflow {ID} (steps length: {M}).` and exit non-zero without writing the file
   - Determine the target field name: `findings` (default) or `rerunFindings` (when `--rerun` is present)
   - Build the base findings object using `jq --argjson` for numeric fields and `--arg` for string fields:
     ```json
     { "errors": N, "warnings": N, "info": N, "decision": "...", "summary": "..." }
     ```
   - When `--details-file` is provided **and** `decision == "auto-advanced"`: read the file, validate it contains a JSON array (`jq -e '. | arrays' <path>`), and merge it as the `details` field. If the file is missing or not a valid JSON array, log `[warn] Could not read details file — recording counts only.` to stderr and write the findings object without `details`.
   - When `--details-file` is provided but `decision != "auto-advanced"`: silently ignore the file (do not write `details`).
   - Write the findings object to `steps[stepIndex].findings` or `steps[stepIndex].rerunFindings` using a `jq` expression of the form:
     ```bash
     jq --argjson idx "$step_index" --argjson obj "$findings_json" \
       ".steps[$idx].${field_name} = \$obj" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
     ```
   - Print the updated state to stdout (consistent with other mutating subcommands)

3. **Wire `record-findings` into the `case` dispatch block** (before the `*)` fallthrough, after `clear-gate`):
   ```bash
   record-findings)
     [[ $# -ge 7 ]] || { echo "Error: record-findings requires <ID> <stepIndex> <errors> <warnings> <info> <decision> <summary> [--rerun] [--details-file <path>]" >&2; exit 1; }
     cmd_record_findings "$@"
     ;;
   ```

4. **Write unit tests** in `scripts/__tests__/workflow-state.test.ts` under a new `describe('record-findings', ...)` block. Cover all eight scenarios from the requirements testing section:
   - `record-findings` writes the correct JSON structure (`errors`, `warnings`, `info`, `decision`, `summary` fields on the step entry) for a valid `stepIndex`
   - `record-findings --rerun` writes to `rerunFindings` without overwriting an existing `findings` field
   - Summary containing shell-special characters (quotes, `$`, backticks, parentheses) is stored verbatim
   - `--details-file` with `decision "auto-advanced"` includes the `details` array in the written object
   - `--details-file` with a non-`auto-advanced` decision omits `details` from the written object
   - `--details-file` pointing to a file with invalid JSON logs the warning and writes without `details`
   - `--details-file` pointing to a non-existent file logs the warning and writes without `details`
   - `stepIndex` equal to the length of the `steps` array (out of bounds) exits non-zero and does not modify the state file
   - `status` subcommand returns findings data when present and works normally when `findings` fields are absent (backwards-compatibility assertion)

   Each test follows the pattern established by existing `record-model-selection` tests: `run('init ... feature')`, then `run('record-findings ... ')`, then `readState()` to assert on the written JSON.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` — `usage()` entry, `cmd_record_findings()` implementation, `case` dispatch entry
- [x] `scripts/__tests__/workflow-state.test.ts` — `describe('record-findings', ...)` block with nine test cases

---

### Phase 2: Orchestrator Integration in `SKILL.md`
**Feature:** [FEAT-016](../features/FEAT-016-persist-review-findings.md) | [#145](https://github.com/lwndev/lwndev-marketplace/issues/145)
**Status:** 🔄 In Progress

#### Rationale

- Depends on Phase 1: the `record-findings` subcommand must exist before the SKILL.md prose instructs the orchestrator to call it. A reader following the SKILL.md instructions would otherwise be calling a nonexistent subcommand.
- All six integration points (FR-5 items 1–6) live within the existing "Reviewing-Requirements Findings Handling" section. They are additive insertions — the Decision Flow and Applying Auto-Fixes prose from FEAT-015 are preserved exactly; only `record-findings` calls and the FR-7 parsing instructions are added.
- Grouping all SKILL.md changes into one phase makes the diff reviewable as a unit and avoids partial states where some decision branches record findings and others do not.
- The FR-7 parsing specification (how to extract individual findings from subagent output for `auto-advanced` decisions) is detailed enough to warrant its own subsection rather than being scattered across the six integration points.

#### Implementation Steps

1. **Add a "Persisting Findings" subsection** immediately after the `#### Applying Auto-Fixes` subsection and before the `### Chain-Specific Step Details` heading. This subsection consolidates the FR-5 call-site table and the FR-7 parsing procedure so neither needs to be repeated at every integration point in the Decision Flow prose:

   Structure:
   ```
   #### Persisting Findings

   At every reviewing-requirements decision point, call `record-findings` **before** `advance` or `pause` to persist the findings in the workflow state file. The call must always precede the state-transition call so that findings survive even if the transition call fails or the process exits.

   ##### Decision-to-Call Mapping

   | Decision taken | `record-findings` invocation |
   |---|---|
   | Zero findings → auto-advance | `record-findings {ID} {stepIndex} 0 0 0 advanced "No issues found"` |
   | Warnings/info only → auto-advance (FEAT-015 gate) | `record-findings {ID} {stepIndex} 0 {W} {I} auto-advanced "{summary}" --details-file {tmp}` |
   | Warnings/info only → user confirmed | `record-findings {ID} {stepIndex} 0 {W} {I} user-advanced "{summary}"` |
   | Warnings/info only → user declined | `record-findings {ID} {stepIndex} 0 {W} {I} paused "{summary}"` |
   | Errors present → user chose "Apply fixes" | `record-findings {ID} {stepIndex} {E} {W} {I} auto-fixed "{summary}"` |
   | Errors present → user chose "Pause" | `record-findings {ID} {stepIndex} {E} {W} {I} paused "{summary}"` |
   | Re-run after auto-fix (any outcome) | `record-findings {ID} {stepIndex} {E2} {W2} {I2} {rerun-decision} "{rerun-summary}" --rerun` |
   | Re-run after auto-fix → auto-advanced | (same as above plus `--details-file {tmp}`) |

   Notes:
   - `{stepIndex}` is the zero-based index in the `steps` array for the current reviewing-requirements step. Use the chain-step-to-index table: feature steps 2/6/6+N+3 map to indices 1/5/6+N+2; chore/bug steps 2/4/7 map to indices 1/3/6.
   - When the subagent returns `"No issues found"` or `Found **0 errors**, **0 warnings**, **0 info**`, normalize to `"No issues found"` as the canonical summary.
   - The `{summary}` must be passed as a single shell-quoted token. Use single quotes around the summary string to handle embedded special characters.

   ##### Parsing Individual Findings for `auto-advanced` Decisions

   When `decision` is `auto-advanced`, parse individual findings from the subagent return text to build the `--details-file` argument:

   1. Scan the subagent return text for lines matching: `**[{W|I}{N}] {category} — {description}**` (or the unbolded variant). The separator is an em dash (`—`, U+2014); accept ASCII double-hyphen (`--`) as a fallback. Map prefix letters: `W` → `"warning"`, `I` → `"info"`.
   2. For each match, extract:
      - `id` — severity+number token (e.g., `"W1"`, `"I3"`)
      - `severity` — mapped from prefix letter
      - `category` — text between `]` and `—`, trimmed
      - `description` — text after `—` to end of line, trimmed and stripped of trailing bold markers
   3. Write the resulting JSON array to `/tmp/findings-{ID}-{stepIndex}.json`
   4. Pass `--details-file /tmp/findings-{ID}-{stepIndex}.json` to `record-findings`
   5. Remove the temp file after `record-findings` returns

   If no individual findings can be parsed despite non-zero counts, write `[]` and log: `[warn] Could not parse individual findings from reviewing-requirements output — recording counts only.`
   ```

2. **Add `record-findings` calls into the Decision Flow subsection** at each of the six integration points. Integrate them as inline bash blocks immediately before each `advance` or `pause` call. The Decision Flow prose structure (items 1, 2, 3) from FEAT-015 is preserved; `record-findings` calls are insertions, not replacements:

   - **Item 1 (Zero findings)**: insert `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-findings {ID} {stepIndex} 0 0 0 advanced "No issues found"` before the `advance` call.
   - **Item 2, auto-advance branch**: insert the FR-7 parsing procedure inline (brief reference to the "Parsing Individual Findings" subsection), then insert the `record-findings ... auto-advanced ... --details-file {tmp}` call before `advance`.
   - **Item 2, prompt branch (user confirms)**: insert `record-findings ... user-advanced ...` before `advance`.
   - **Item 2, prompt branch (user declines)**: insert `record-findings ... paused ...` before `pause`.
   - **Item 3, "Apply fixes" branch**: insert `record-findings ... auto-fixed ...` at the decision point (before beginning fix application). The re-run's `record-findings --rerun` call is added in the Applying Auto-Fixes section.
   - **Item 3, "Pause" branch**: insert `record-findings ... paused ...` before `pause`.

3. **Add `record-findings --rerun` calls into the Applying Auto-Fixes subsection** at each re-run outcome branch in step 4. The "do not apply further edits" rule and the three outcome branches (zero errors, warnings/info only, errors) are preserved from FEAT-015; `record-findings --rerun` calls are inserted before each `clear-gate`/`advance`/`pause` call:

   - Zero errors re-run outcome: insert `record-findings {ID} {stepIndex} 0 0 0 advanced "{rerun-summary}" --rerun` before `clear-gate`.
   - Warnings/info only re-run outcome: run the FR-7 parsing procedure; insert `record-findings {ID} {stepIndex} 0 {W2} {I2} auto-advanced "{rerun-summary}" --rerun --details-file {tmp}` before `clear-gate`.
   - Errors re-run outcome: insert `record-findings {ID} {stepIndex} {E2} {W2} {I2} paused "{rerun-summary}" --rerun` before `pause`.

4. **Add a note to the Parsing Findings subsection** clarifying that the count-extraction regex must anchor on the `Found **N errors**` substring (not the line start) to handle the test-plan and code-review mode prefixes (e.g., `"Test-plan reconciliation for {ID}: Found **N errors**..."`).

5. **Verify the edit** by reading lines 248–340 of the updated SKILL.md and confirming:
   - Every decision branch in the Decision Flow has a `record-findings` call placed before its `advance` or `pause` call
   - The `--rerun` calls appear in Applying Auto-Fixes before the corresponding `clear-gate`/`pause` calls
   - The FEAT-015 auto-advance gate logic (`type` + `complexity` reads) is unchanged
   - The gate (`set-gate` / `clear-gate`) calls are still present at the correct positions
   - The skipped-step paths (CHORE-031 `advance` without fork) have no `record-findings` call
   - Step index values in the prose examples match the chain-step-to-index table

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — "Persisting Findings" subsection (including decision-to-call table and FR-7 parsing procedure), `record-findings` calls in Decision Flow items 1–3, `record-findings --rerun` calls in Applying Auto-Fixes step 4

---

## Shared Infrastructure

No new shared utilities are introduced. `jq` is already a declared dependency of `workflow-state.sh`. Temp file paths follow the existing `/tmp/` convention used elsewhere in orchestrator prose.

## Testing Strategy

### Unit Tests (Phase 1)

Shell script tests live in `scripts/__tests__/workflow-state.test.ts` and run via the existing vitest harness with `fileParallelism: false`. Each test runs the actual `workflow-state.sh` bash script in a fresh `tmpdir` working directory (same pattern as the FEAT-014 tests). The nine test cases cover all edge paths for `record-findings` — correct writes, `--rerun` isolation, shell-special-character safety, conditional `details` inclusion, error recovery for bad `--details-file`, and out-of-bounds `stepIndex`.

### Manual Testing (Phase 2)

The requirements manual-testing matrix covers five scenarios:

| Scenario | Verification |
|---|---|
| Bug/chore workflow, zero findings | `findings.decision == "advanced"` on the step entry |
| Bug/chore workflow (complexity ≤ medium), warnings-only | `findings.decision == "auto-advanced"` with populated `details` array |
| Feature workflow, warnings-only, user confirms | `findings.decision == "user-advanced"` without `details` |
| Workflow with errors → apply fixes → re-run succeeds | `findings.decision == "auto-fixed"` and `rerunFindings.decision == "advanced"` |
| Workflow with errors → apply fixes → re-run still has errors | `findings.decision == "auto-fixed"` and `rerunFindings.decision == "paused"` |
| Workflow with errors → user pauses | `findings.decision == "paused"` without `rerunFindings` |
| Completed workflow | All non-skipped reviewing-requirements steps have `findings` |

Inspection command:
```bash
jq '[.steps[] | select(.skill == "reviewing-requirements") | {name, findings, rerunFindings}]' \
  ".sdlc/workflows/{ID}.json"
```

## Dependencies and Prerequisites

- **FEAT-015 / #139** — The `auto-advanced` decision value and the FEAT-015 auto-advance gate (item 2's chain-type/complexity check) must be in place before Phase 2 integration calls can reference `auto-advanced` paths. FEAT-015 is already merged.
- **`jq`** — Already a declared dependency; no version requirement beyond what is currently in use.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Shell-quoting issue with `summary` arg containing embedded quotes | Medium | Low | Use `--arg` (not `--argjson`) for all string fields in `jq`; single-quote the summary token at every call site in SKILL.md prose |
| `record-findings` call placed after `advance`/`pause` instead of before | Medium | Low | NFR-3 states the ordering requirement explicitly; Phase 2 verification step confirms ordering before the phase is marked complete |
| `details` written for non-`auto-advanced` decisions due to mis-read flag logic | Low | Low | Unit test "non-`auto-advanced` decision ignores `--details-file`" catches this directly |
| FR-7 parsing fails for all findings despite non-zero counts | Low | Low | Fallback to empty `[]` with a warn log keeps the write non-fatal; counts from the summary line remain authoritative |
| Out-of-bounds `stepIndex` silently writes garbage due to jq array expansion | Medium | Low | Explicit length check in `cmd_record_findings` before any `jq` write; unit test asserts non-zero exit and no file mutation |

## Success Criteria

- [ ] After every non-skipped reviewing-requirements step, the state file contains a `findings` object on the step entry with `errors`, `warnings`, `info`, `decision`, and `summary` fields
- [ ] Auto-advanced steps include a `findings` record with a populated `details` array
- [ ] Non-auto-advanced steps include a `findings` record without a `details` field
- [ ] When auto-fixes are applied and a re-run occurs, both `findings` and `rerunFindings` are present on the step entry
- [ ] When `rerunFindings.decision` is `"auto-advanced"`, `rerunFindings` includes a `details` array
- [ ] Skipped steps (CHORE-031 low-complexity) have no `findings` field
- [ ] Existing workflow state files without `findings` fields remain valid (backwards-compatible; `status` subcommand returns full state including absence of these fields without error)
- [ ] The Decision Flow logic is unchanged — `record-findings` is additive and does not influence advance/pause decisions

## Code Organization

All changes are confined to two files:

```
plugins/lwndev-sdlc/skills/orchestrating-workflows/
├── scripts/
│   └── workflow-state.sh            ← Phase 1: usage(), cmd_record_findings(), case dispatch
└── SKILL.md                         ← Phase 2: "Persisting Findings" subsection + call sites

scripts/__tests__/
└── workflow-state.test.ts           ← Phase 1: describe('record-findings', ...) block
```

No new files are created. No other skills, state-file schemas at the top level, or subcommand behaviors are modified.
