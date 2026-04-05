# Implementation Plan: Releasing Stop Hook State-File Scoping

## Overview

Replace the keyword-based pattern exclusion in the `releasing-plugins` stop hook with a state-file approach using marker files in `.sdlc/releasing/`. The current keyword guard (`grep -qE "(release|version|bump|...)"`) produces false positives when messages incidentally contain release-related terms (e.g., discussing bug summaries that mention "releasing-plugins" or "Phase 1"). By switching to explicit marker files that are only written when the releasing skill is actively invoked, the stop hook can determine whether a release workflow is in progress without inspecting message content for context cues.

Two files are modified: the bash stop hook script and the SKILL.md instructions. No new files are created at rest -- the marker files are transient, written during a release and cleaned up on completion.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-013   | [#125](https://github.com/lwndev/lwndev-marketplace/issues/125) | [FEAT-013-releasing-stop-hook-state-file.md](../features/FEAT-013-releasing-stop-hook-state-file.md) | Medium | Low | Pending |

## Recommended Build Sequence

### Phase 1: Stop Hook State-File Logic
**Feature:** [FEAT-013](../features/FEAT-013-releasing-stop-hook-state-file.md) | [#125](https://github.com/lwndev/lwndev-marketplace/issues/125)
**Status:** ✅ Complete

#### Rationale
- The stop hook script is the enforcement mechanism -- it must be updated first so the state-file gates are in place before SKILL.md starts writing markers
- Modifying the script in isolation is safe: without marker files present, the hook will `exit 0` on every invocation, which is the correct behavior when no release is in progress
- This phase establishes the contract (file paths, semantics) that Phase 2 depends on

#### Implementation Steps

1. **Create the state-file directory constant** -- at the top of `stop-hook.sh`, define `STATE_DIR=".sdlc/releasing"` so all file paths reference a single variable

2. **Add the `.active` file gate** -- immediately after the `stop_hook_active` bypass (line 22) and before extracting `last_assistant_message`, insert a check:
   - If `"$STATE_DIR/.active"` does not exist, `exit 0` (no release workflow in progress, allow stop)
   - Wrap the file-existence test in a subshell or use `||` to ensure I/O errors fail open (`exit 0`)

3. **Add the `.phase1-complete` early exit** -- after the `.active` check confirms a release is in progress, before any message pattern matching:
   - If `"$STATE_DIR/.phase1-complete"` exists, `exit 0` (Phase 1 is done; skip all Phase 1 criteria checks and allow stop unless Phase 2 patterns are detected below)

4. **Remove the keyword guard** -- delete lines 33-36 (the `grep -qE "(release|version|bump|changelog|tag the|phase 1|phase 2|plugin.*v[0-9])"` block). The `.active` gate fully replaces this logic.

5. **Restructure Phase 2 detection and cleanup** -- within the existing Phase 2 block (currently lines 57-69):
   - When Phase 2 tag-pushed criteria are met, add cleanup: `rm -f "$STATE_DIR/.active" "$STATE_DIR/.phase1-complete" 2>/dev/null` before `exit 0`
   - Ensure cleanup failures are logged to stderr but do not block: use `|| echo "Warning: cleanup of $STATE_DIR markers failed" >&2` as a guard

6. **Preserve existing guards unchanged** -- verify that the following remain unmodified:
   - Empty/malformed input guard (lines 13-16)
   - `stop_hook_active` bypass (lines 18-22)
   - `jq` parse failure fallback (`|| exit 0`)
   - Phase 1 pattern matching logic (PR created + re-invoke detection) -- still needed to validate criteria *within* an active release
   - Phase 2 pattern matching logic (tag pushed detection) -- still needed to validate Phase 2 criteria

7. **Add fail-open error handling for marker file reads** -- ensure all file-existence tests (`[[ -f ... ]]`) and any `cat` of marker files use `|| exit 0` so that permission errors or I/O failures allow stop rather than trapping the user

8. **Test the modified script manually** by running the four key scenarios:
   - No `.active` file exists -> `exit 0`
   - `.active` exists, no `.phase1-complete`, Phase 1 criteria not met -> `exit 2`
   - `.active` exists, `.phase1-complete` exists -> `exit 0`
   - `.active` exists, Phase 2 tag-pushed criteria met -> `exit 0` and markers cleaned up

#### Deliverables
- [x] `.claude/skills/releasing-plugins/scripts/stop-hook.sh` -- updated with state-file gates, keyword guard removed, Phase 2 cleanup added

---

### Phase 2: SKILL.md Marker File Instructions
**Feature:** [FEAT-013](../features/FEAT-013-releasing-stop-hook-state-file.md) | [#125](https://github.com/lwndev/lwndev-marketplace/issues/125)
**Status:** 🔄 In Progress

#### Rationale
- SKILL.md is the instruction document that tells Claude *when* to write and clean up marker files
- It depends on Phase 1 having established the file paths and semantics in the stop hook
- Changes are additive -- inserting marker-write steps at specific points in the existing Phase 1 / Phase 2 workflow

#### Implementation Steps

1. **Add Phase 1 start marker** -- in the Phase 1 section, after step 1 ("Identify the plugin and scope") and before step 2 ("Review unreleased changes"), add a new instruction:
   - Create the `.sdlc/releasing/` directory: `mkdir -p .sdlc/releasing`
   - Write the `.active` marker with the plugin name: `echo "<plugin-name>" > .sdlc/releasing/.active`
   - Explain that this signals to the stop hook that a release workflow is in progress

2. **Add Phase 1 complete marker** -- after step 8 ("Remind about Phase 2"), add an instruction:
   - Write the `.phase1-complete` marker with the PR number: `echo "<pr-number>" > .sdlc/releasing/.phase1-complete`
   - Explain that this allows the stop hook to skip Phase 1 criteria checks, preventing false positives when the user performs unrelated work between phases

3. **Add Phase 2 cleanup** -- after step 3 ("Push the tag") in Phase 2, add an instruction:
   - Remove all marker files: `rm -rf .sdlc/releasing/`
   - Explain that this completes the release lifecycle and prevents stale markers

4. **Add cancellation instructions** -- add a new section "Cancellation" (or append to an existing notes section):
   - If the user explicitly cancels the release at any point, remove the `.sdlc/releasing/` directory and all its contents: `rm -rf .sdlc/releasing/`
   - Explain that this ensures the stop hook returns to its default pass-through behavior

5. **Verify instruction ordering** -- confirm that the marker-write steps are positioned correctly relative to existing steps:
   - `.active` is written *after* the plugin is identified (so the file contains a valid plugin name) and *before* any release operations begin
   - `.phase1-complete` is written *after* the PR is created and the Phase 2 reminder is delivered
   - Cleanup runs *after* the tag is pushed

#### Deliverables
- [ ] `.claude/skills/releasing-plugins/SKILL.md` -- updated with marker file write/cleanup instructions at Phase 1 start, Phase 1 complete, Phase 2 complete, and cancellation

---

## Shared Infrastructure

### State Directory Convention

The `.sdlc/releasing/` directory follows the existing `.sdlc/workflows/` convention for workflow state. No new shared libraries or utilities are needed -- the implementation uses pure bash file operations (`mkdir -p`, `echo >`, `rm -rf`, `[[ -f ... ]]`).

### Marker File Format

Both marker files are plain text with a single line of content for traceability:
- `.sdlc/releasing/.active` -- contains the plugin name (e.g., `lwndev-sdlc`)
- `.sdlc/releasing/.phase1-complete` -- contains the PR number (e.g., `126`)

The stop hook only checks file *existence*, not content. The content is for human debugging if markers are found in an unexpected state.

## Testing Strategy

### Manual Testing (Primary)

Since the stop hook is a bash script invoked by the Claude Code harness, automated unit testing is impractical. Manual testing covers:

1. **No release in progress** -- verify stop is allowed on any message (no `.active` file)
2. **Phase 1 active, criteria not met** -- verify stop is blocked when `.active` exists but Phase 1 criteria are missing
3. **Phase 1 active, criteria met** -- verify stop is allowed and `.phase1-complete` is written
4. **Between phases** -- perform unrelated work after Phase 1; verify stop is allowed (`.phase1-complete` exists)
5. **Phase 2 active, tag not pushed** -- verify stop is blocked
6. **Phase 2 complete** -- verify stop is allowed and all markers are cleaned up
7. **False positive regression** -- discuss release-related topics (e.g., "the releasing-plugins stop hook had a bug in Phase 1") without an active release; verify stop is allowed

### Integration Testing

- Invoke `/releasing-plugins` end-to-end and verify marker files are created and cleaned up at the correct lifecycle points
- Verify stale `.active` files from abandoned releases do not interfere with non-release work

## Dependencies and Prerequisites

### Existing Code (Modified)
- `.claude/skills/releasing-plugins/scripts/stop-hook.sh` -- the bash stop hook (86 lines)
- `.claude/skills/releasing-plugins/SKILL.md` -- the skill instructions

### Existing Infrastructure (Unchanged)
- `.sdlc/` directory -- already exists in the repository for workflow state
- `jq` -- used by the stop hook for JSON parsing (no change)
- Claude Code harness -- invokes the stop hook and reads exit codes (no change)

### No New Dependencies
- No new packages, tools, or external services required
- Pure bash file operations for all state management

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Stale `.active` file from abandoned release blocks future releases | Low | Medium | The stop hook only *blocks* when `.active` exists and criteria are unmet. A stale `.active` from a previous conversation does not block non-release work (no keyword matching). A new release invocation overwrites the file. |
| Marker file I/O failure (permissions, disk full) traps the user | High | Low | All file-existence checks fail open (`exit 0`). The hook never blocks due to I/O errors. |
| SKILL.md instructions not followed (Claude skips marker write) | Medium | Low | The stop hook's `.active` gate means that if markers are never written, the hook always allows stop -- it degrades to no enforcement rather than false positives. |
| Phase 2 cleanup fails, leaving stale markers | Low | Low | Cleanup uses `rm -rf` which is idempotent. If it fails, a warning is logged to stderr. Stale `.phase1-complete` only causes the hook to skip Phase 1 checks, which is harmless after Phase 2. |
| Regression in Phase 1/2 pattern matching logic | Medium | Low | Pattern matching logic (lines 38-85) is unchanged. Only the entry gate is modified. |

## Success Criteria

### Per-Phase Criteria

**Phase 1 (Stop Hook):**
- Stop hook exits 0 when no `.active` marker exists
- Stop hook checks Phase 1 criteria when `.active` exists but `.phase1-complete` does not
- Stop hook exits 0 when `.phase1-complete` exists
- Stop hook cleans up markers after Phase 2 tag-pushed detection
- Stop hook exits 0 (allows stop) on any I/O error during marker checks
- Keyword guard (`grep -qE`) is removed

**Phase 2 (SKILL.md):**
- `.active` marker written after plugin identification, before release operations
- `.phase1-complete` marker written after PR creation and Phase 2 reminder
- Markers cleaned up after tag push in Phase 2
- Cancellation instructions included for explicit user cancellation

### Overall Success
- No false positives: discussing release-related topics outside a release workflow does not trigger the stop hook
- No false negatives: the stop hook still blocks premature stops during an active release
- All 10 acceptance criteria from the requirements document are met

## Code Organization

```
.claude/skills/releasing-plugins/
├── scripts/
│   └── stop-hook.sh          # Modified: state-file gates, keyword guard removed
└── SKILL.md                  # Modified: marker file instructions added

.sdlc/
├── releasing/                # Transient: created/removed during release workflow
│   ├── .active               # Written at Phase 1 start, removed at Phase 2 end
│   └── .phase1-complete      # Written at Phase 1 end, removed at Phase 2 end
└── workflows/                # Existing: unrelated workflow state
```
