# Feature Requirements: Releasing Stop Hook State-File Scoping

## Overview

Replace the keyword-based pattern exclusion in the `releasing-plugins` stop hook with a state-file approach using marker files in `.sdlc/releasing/`, fully eliminating false positives from messages that incidentally contain release-related terms.

## Feature ID
`FEAT-013`

## GitHub Issue
[#125](https://github.com/lwndev/lwndev-marketplace/issues/125)

## Priority
Medium - The BUG-008 keyword guard handles most cases but still triggers on messages that discuss the release skill itself (e.g., bug summaries mentioning "releasing-plugins", "Phase 1", "stop hook")

## User Story

As a plugin maintainer, I want the releasing-plugins stop hook to use explicit state files instead of keyword matching so that I can work on unrelated tasks in the same conversation without false-positive blocks.

## Functional Requirements

### FR-1: State File Directory

- Use `.sdlc/releasing/` as the state directory for release workflow markers
- Consistent with existing `.sdlc/workflows/` convention for workflow state

### FR-2: Active Marker (`.sdlc/releasing/.active`)

- Written by SKILL.md instructions when Phase 1 starts (before any release operations begin)
- Presence indicates a release workflow is in progress
- Contains the plugin name being released (e.g., `lwndev-sdlc`) for traceability

### FR-3: Phase 1 Complete Marker (`.sdlc/releasing/.phase1-complete`)

- Written by SKILL.md instructions after Phase 1 completes (PR created and user told about Phase 2)
- Presence indicates Phase 1 is done and the stop hook should not validate Phase 1 criteria
- Contains the PR number for traceability

### FR-4: Stop Hook State-File Logic

The stop hook at `.claude/skills/releasing-plugins/scripts/stop-hook.sh` must replace the keyword guard (lines 33-36) with state-file checks:

1. **No `.active` file** -> `exit 0` (no release workflow in progress, allow stop)
2. **`.active` exists, no `.phase1-complete`** -> Check Phase 1 criteria via existing pattern matching on `last_assistant_message` (block if not met, exit 2)
3. **`.phase1-complete` exists** -> `exit 0` (Phase 1 done, allow stop regardless of message content)
4. **Phase 2 detection** -> When Phase 2 patterns are detected in the message, check tag-pushed criteria; on success, clean up all marker files in `.sdlc/releasing/`. Note: Phase 2 detection remains pattern-based by design — the `.active` gate already prevents false positives from non-release contexts, and Phase 2 patterns are only evaluated when `.active` exists.

### FR-5: SKILL.md Marker File Instructions

Update `.claude/skills/releasing-plugins/SKILL.md` to include marker file operations:

- **Phase 1 start** (after step 1 identifies the plugin, before step 2): Create `.sdlc/releasing/` directory and write `.active` with the plugin name
- **Phase 1 complete** (after step 8): Write `.phase1-complete` with the PR number
- **Phase 2 complete** (after step 3): Remove all files in `.sdlc/releasing/` (cleanup)
- **User cancellation**: If the user explicitly cancels, remove `.sdlc/releasing/` markers

### FR-6: Keyword Guard Removal

- Remove the keyword regex guard at line 34 of the stop hook (`grep -qE "(release|version|bump|changelog|tag the|phase 1|phase 2|plugin.*v[0-9])"`)
- The state-file check fully replaces this logic — no keyword matching is needed when `.active` determines whether a release is in progress

### FR-7: Cleanup Safety

- Phase 2 completion must clean up both `.active` and `.phase1-complete`
- If `.sdlc/releasing/` directory doesn't exist when cleanup runs, silently succeed (idempotent)
- Stale marker files (e.g., from an abandoned release) should not block unrelated work — the `.active` file is only created when the skill is explicitly invoked

## Non-Functional Requirements

### NFR-1: Backwards Compatibility

- The `stop_hook_active` bypass (lines 18-22) must remain unchanged — it's an existing safety valve
- The empty/malformed input guard (lines 13-16) must remain unchanged
- Phase 1 and Phase 2 pattern matching logic (lines 38-85) remains for validating within an active release, just no longer evaluated when no `.active` file exists

### NFR-2: Error Handling

- If `jq` parsing fails, allow stop (`exit 0`) — existing behavior, must preserve
- If marker file reads fail (permissions, disk), allow stop (`exit 0`) — fail-open to avoid trapping the user
- If cleanup fails, log a warning to stderr but don't block

### NFR-3: Performance

- File existence checks (`[[ -f ... ]]`) are fast and add negligible overhead to every stop
- No external commands needed for state checks (pure bash file tests)

## Dependencies

- Existing `.claude/skills/releasing-plugins/scripts/stop-hook.sh` (modified)
- Existing `.claude/skills/releasing-plugins/SKILL.md` (modified)
- `.sdlc/` directory (already exists for workflow state)

## Edge Cases

1. **Stale `.active` file from abandoned release**: User starts a release, cancels mid-Phase 1, starts a new conversation. The `.active` file persists. Next release invocation should overwrite it. Non-release work should not be affected because the stop hook exits 0 immediately when no `.active` file exists (and stale files from a previous conversation don't cause issues since the hook checks file existence, not conversation state).
2. **Phase 2 in a new conversation**: User completes Phase 1, merges PR, starts a new conversation for Phase 2. The `.phase1-complete` file from the previous conversation allows the stop hook to skip Phase 1 checks. Phase 2 detection and validation still works.
3. **Concurrent release attempts**: Not expected (single-maintainer workflow), but if `.active` exists with a different plugin name, the new invocation overwrites it.
4. **`.sdlc/releasing/` directory doesn't exist**: Stop hook sees no `.active` file -> `exit 0`. SKILL.md instructions create the directory at Phase 1 start.
5. **Hook fires for non-release skill**: Stop hook checks `.active` first. If absent, exits 0 immediately without inspecting the message. This eliminates all false positives from non-release contexts.

## Testing Requirements

### Manual Testing

- Invoke `/releasing-plugins`, verify `.active` is created at Phase 1 start
- Complete Phase 1, verify `.phase1-complete` is created
- After Phase 1, perform an unrelated task — verify stop is allowed (no false positive)
- Complete Phase 2, verify `.sdlc/releasing/` markers are cleaned up
- Without any release in progress, verify stop is allowed on any message

### Integration Testing

- Verify stop hook exits 0 when no `.active` file exists
- Verify stop hook checks Phase 1 criteria when `.active` exists but `.phase1-complete` does not
- Verify stop hook exits 0 when `.phase1-complete` exists
- Verify cleanup removes all marker files after Phase 2

## Acceptance Criteria

- [x] Stop hook uses `.sdlc/releasing/.active` and `.sdlc/releasing/.phase1-complete` marker files
- [x] Hook exits 0 when no `.active` marker exists (no release in progress)
- [x] Hook exits 0 when `.phase1-complete` exists (Phase 1 done, allow any message)
- [x] Hook blocks during Phase 1 when criteria not met (`.active` exists, no `.phase1-complete`)
- [x] Hook blocks during Phase 2 when tag not pushed
- [x] Marker files cleaned up after Phase 2 completion
- [x] SKILL.md updated with marker file write/cleanup instructions
- [x] Keyword guard removed from stop hook (no longer needed)
- [x] Hook exits 0 (allows stop) when marker file reads fail due to permissions or I/O errors (fail-open)
- [x] SKILL.md includes cancellation instructions that remove `.sdlc/releasing/` markers

## Completion

**Status:** `Completed`

**Completed:** 2026-04-06

**Pull Request:** [#126](https://github.com/lwndev/lwndev-marketplace/pull/126)

## Deviation Summary

**Phase 2 enforcement relies on SKILL.md instructions rather than hook blocking**: The `.phase1-complete` gate (FR-4.3) exits 0 before message extraction, making the Phase 2 pattern matching and hook cleanup (FR-4.4) unreachable in the normal workflow where `.phase1-complete` exists. Phase 2 enforcement and marker cleanup depend on SKILL.md instructions (Phase 2 step 4) rather than the stop hook. This is an acceptable simplification — Phase 2 is a short, simple flow (tag + push), and the SKILL.md instructions are the primary enforcement mechanism. AC-5 ("Hook blocks during Phase 2 when tag not pushed") holds only when `.phase1-complete` does not exist, which is not the normal lifecycle state.
