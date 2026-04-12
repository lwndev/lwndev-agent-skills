# Implementation Plan: Fix Findings-Handling Spiral on Bug/Chore Chains

## Overview

This plan covers the prose-only changes to `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` required by FEAT-015. Two subsections within the "Reviewing-Requirements Findings Handling" section are rewritten: **Decision Flow** (to add a chain-type/complexity gate on the warnings-only branch) and **Applying Auto-Fixes** (to make the no-edits-after-re-run rule unambiguous). No executable code, tests, or schema changes are involved.

## Features Summary

| ID | Name | Priority | Complexity | Status |
|----|------|----------|------------|--------|
| FEAT-015 | Fix Findings-Handling Spiral on Bug/Chore Chains | Medium | Low | 🔄 In Progress |

## Recommended Build Sequence

Because the change is entirely contained within two adjacent subsections of a single file, a single phase is appropriate.

### Phase 1: Rewrite Decision Flow and Applying Auto-Fixes Subsections

**Rationale**

Both subsections must be updated together: the Decision Flow introduces the chain-type/complexity gate (FR-1, FR-2) and the informational log format (FR-4), while Applying Auto-Fixes strengthens the terminal re-run rule (FR-3). The two subsections are coupled — the Decision Flow's "Errors present / Apply fixes" branch references the Applying Auto-Fixes section, and both must be coherent after the edit.

**Target file**

`plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md`
Lines 262–295 (the `#### Decision Flow` and `#### Applying Auto-Fixes` subsections).

**Implementation Steps**

1. **Replace the `#### Decision Flow` subsection** (lines 262–286) with the new text below. The zero-findings branch (item 1) and errors-present branch (item 3) are unchanged in logic; only item 2 is split into a gated sub-tree.

   New Decision Flow text:

   ```
   #### Decision Flow

   Based on the parsed counts, follow this flow:

   1. **Zero findings** (zero errors, zero warnings, zero info) → Advance state automatically. No user interaction needed.

   2. **Warnings/info only (zero errors)** → Read chain type and complexity from the state file:
      ```bash
      type=$(jq -r '.type' ".sdlc/workflows/{ID}.json")
      complexity=$(jq -r '.complexity // "medium"' ".sdlc/workflows/{ID}.json")
      ```
      Apply the gate:
      - **Bug or chore chain with `complexity == low` or `complexity == medium`** → Log the findings and auto-advance:
        ```
        [info] {N} warnings, {N} info from reviewing-requirements ({mode}) — auto-advancing (chain={type}, complexity={complexity})
        ```
        Display the full findings to the user (for visibility), emit the `[info]` line above, then advance state. Do not prompt.
      - **Bug or chore chain with `complexity == high`**, or **any feature chain** → Display the full findings to the user. Prompt: "{N} warnings and {N} info found by reviewing-requirements. Review findings above and continue? (yes / no)". If the user confirms, advance state. If the user declines, pause the workflow:
        ```bash
        ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} review-findings
        ```
        Halt execution. The user re-invokes with `/orchestrating-workflows {ID}` after addressing findings manually.

   3. **Errors present** → Display the full findings to the user. List the auto-fixable items from the "Fix Summary" / "Update Summary" section of the findings. Errors always block progression — present two options:
      - **Apply fixes** → The orchestrator applies the auto-fixable corrections in main context using the Edit tool. Then spawn a **new** `reviewing-requirements` subagent fork to re-verify (this is the re-run, max 1). Parse the re-run findings per the rules in "Applying Auto-Fixes" below.
      - **Pause for manual resolution** → Pause immediately:
        ```bash
        ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} review-findings
        ```
        Halt execution.
   ```

2. **Replace the `#### Applying Auto-Fixes` subsection** (lines 288–295) with the strengthened text below. Step 4 is expanded to cover all three re-run outcomes explicitly and makes clear that no further edits occur regardless of findings.

   New Applying Auto-Fixes text:

   ```
   #### Applying Auto-Fixes

   When the user opts to apply fixes, the orchestrator (not a subagent) applies them:

   1. Read the auto-fixable items from the findings (listed under "Auto-fixable" or "Applicable updates" in the subagent's return text)
   2. For each fix, use the Edit tool to apply the correction to the target file
   3. After all fixes are applied, spawn a new `reviewing-requirements` subagent fork with the same arguments as the original step to re-verify
   4. This re-run is the single allowed retry. After the re-run completes, **do not apply any further edits regardless of what the re-run findings contain**:
      - If the re-run returns zero errors → advance state.
      - If the re-run returns warnings/info only (zero errors) → advance state unconditionally. Zero errors after a fix pass means the fixes succeeded; residual warnings are accepted.
      - If the re-run returns errors → display the remaining findings and pause with `review-findings`. Do not attempt to fix the errors.
        ```bash
        ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} review-findings
        ```
        Halt execution.
   ```

3. **Verify the edit** by reading lines 262–300 of the updated file and confirming:
   - The `jq` state-file reads use the correct field paths (`.type`, `.complexity // "medium"`).
   - The `[info]` log line exactly matches the FR-4 format: `[info] {N} warnings, {N} info from reviewing-requirements ({mode}) — auto-advancing (chain={type}, complexity={complexity})`.
   - The "Applying Auto-Fixes" step 4 lists all three re-run outcomes (zero errors, warnings/info only, errors) and none of the branches trigger further edits.
   - Feature-chain behavior is unchanged (still prompts on warnings-only for all complexities).
   - High-complexity bug/chore behavior is unchanged (still prompts).

**Deliverables**

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` with updated Decision Flow and Applying Auto-Fixes subsections.

## Shared Infrastructure

None. This is a prose change to a single file with no shared utilities.

## Testing Strategy

Per the requirements (NFR-2), unit and integration tests are not applicable — the changes are behavioral instructions for the orchestrator, not executable code.

Manual verification scenarios (from the requirements):

| Scenario | Expected Result |
|---|---|
| Bug/chore chain, `complexity == low` or `medium`, warnings-only findings | Auto-advance without prompt; `[info]` line logged |
| Bug/chore chain, `complexity == high`, warnings-only findings | User prompted; behavior unchanged |
| Feature chain, any complexity, warnings-only findings | User prompted; behavior unchanged |
| Any chain: user applies fixes, re-run returns warnings | No further edits; state advances |
| Any chain: user applies fixes, re-run returns errors | No further edits; workflow pauses with `review-findings` |
| State file has `null` complexity field | Treated as `medium`; bug/chore auto-advances on warnings-only |

## Dependencies and Prerequisites

- None. FEAT-014 (adaptive model selection) persists `.type` and `.complexity` to the state file and is already merged. The `jq` reads introduced here rely on fields that are guaranteed to exist post-FEAT-014 (with null-coalescing for pre-FEAT-014 migrated state).

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|---|---|---|---|
| Prose ambiguity in the gating condition leaves room for LLM interpretation | Medium | Low | Write the gate as an explicit `if/else` tree keyed on literal string values (`"bug"`, `"chore"`, `"feature"`, `"low"`, `"medium"`, `"high"`) so there is no room for judgment |
| The `jq` null-coalescing expression is misread and null complexity is not treated as medium | Low | Low | Use the exact expression `jq -r '.complexity // "medium"'` in the prose; note its behavior explicitly |
| Feature-chain regression — interactive prompt removed for feature chains by accident | High | Low | Item 2's gate explicitly lists `any feature chain` as retaining the prompt; verify this in step 3 of the implementation |
| Edits after re-run still occur because the "do not apply further edits" rule is buried | Medium | Low | Rewrite step 4 to be the dominant statement (`do not apply any further edits regardless...`) rather than a subordinate qualifier |

## Success Criteria

- [ ] Bug/chore chains with `complexity <= medium` auto-advance on warnings-only findings from `reviewing-requirements` (all modes: standard, test-plan, code-review)
- [ ] The "no edits after re-run" rule is unambiguous — the re-run is terminal regardless of findings content
- [ ] Feature-chain behavior is completely unchanged at all complexities
- [ ] `complexity == high` bug/chore chains still prompt the user on warnings-only findings
- [ ] Auto-advanced findings are logged with the exact `[info]` format from FR-4
- [ ] Null complexity is treated as medium (null-coalescing in jq expression)

## Code Organization

All changes are confined to:

```
plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md
  └── ### Reviewing-Requirements Findings Handling
        ├── #### Decision Flow          ← FR-1, FR-2, FR-4 (lines ~262–286)
        └── #### Applying Auto-Fixes   ← FR-3              (lines ~288–295)
```

No other files are modified.
