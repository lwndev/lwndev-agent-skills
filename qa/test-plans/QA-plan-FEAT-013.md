# QA Test Plan: Releasing Stop Hook State-File Scoping

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-FEAT-013 |
| **Requirement Type** | FEAT |
| **Requirement ID** | FEAT-013 |
| **Source Documents** | `requirements/features/FEAT-013-releasing-stop-hook-state-file.md`, `requirements/implementation/FEAT-013-releasing-stop-hook-state-file.md` |
| **Date Created** | 2026-04-05 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/build.test.ts` | Validates all plugins pass `npm run validate` | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| Stop hook exits 0 when no `.active` file exists (no release in progress) | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | FR-4.1, AC-2 | High | PASS |
| Stop hook checks Phase 1 criteria when `.active` exists but `.phase1-complete` does not | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | FR-4.2, AC-4 | High | PASS |
| Stop hook exits 0 when `.phase1-complete` exists (Phase 1 done) | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | FR-4.3, AC-3 | High | PASS |
| Stop hook blocks during Phase 2 when tag not pushed | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | FR-4.4, AC-5 | High | PASS |
| Stop hook cleans up markers after Phase 2 tag-pushed criteria met | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | FR-4.4, FR-7, AC-6 | High | PASS |
| Keyword guard (`grep -qE`) is removed from stop hook | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | FR-6, AC-8 | High | PASS |
| Stop hook exits 0 (fail-open) when marker file reads fail due to I/O errors | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | NFR-2, AC-9 | Medium | PASS |
| `stop_hook_active` bypass remains functional and unchanged | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | NFR-1 | Medium | PASS |
| Empty/malformed input guard remains functional and unchanged | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | NFR-1 | Medium | PASS |
| SKILL.md includes `.active` marker write after step 1, before step 2 | `.claude/skills/releasing-plugins/SKILL.md` | FR-5, AC-7 | High | PASS |
| SKILL.md includes `.phase1-complete` marker write after step 8 | `.claude/skills/releasing-plugins/SKILL.md` | FR-5, AC-7 | High | PASS |
| SKILL.md includes Phase 2 cleanup instructions after tag push | `.claude/skills/releasing-plugins/SKILL.md` | FR-5, AC-6 | High | PASS |
| SKILL.md includes cancellation cleanup instructions | `.claude/skills/releasing-plugins/SKILL.md` | FR-5, AC-10 | Medium | PASS |
| State directory uses `.sdlc/releasing/` path | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | FR-1, AC-1 | Medium | PASS |
| `.active` marker content contains plugin name for traceability | `.claude/skills/releasing-plugins/SKILL.md` | FR-2 | Low | PASS |
| `.phase1-complete` marker content contains PR number for traceability | `.claude/skills/releasing-plugins/SKILL.md` | FR-3 | Low | PASS |

## Coverage Gap Analysis

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| End-to-end test of full release lifecycle with marker file creation/cleanup | Both modified files | FR-2, FR-3, FR-5 | Manual testing: invoke `/releasing-plugins`, verify markers appear at correct lifecycle points and are cleaned up |
| Stale `.active` file from abandoned release blocks stops until `.active` is removed | Stop hook script | Edge Case 1 | Manual testing: create `.sdlc/releasing/.active` manually, pipe a non-release JSON message to the hook, verify exit 2 (block) per FR-4.2 — when `.active` exists and `.phase1-complete` does not, the hook checks Phase 1 criteria and blocks if unmet. To unblock, the user must either complete the release, start a new release (which overwrites `.active`), or manually remove `.sdlc/releasing/.active`. |
| Phase 2 in a new conversation with existing `.phase1-complete` | Stop hook + SKILL.md | Edge Case 2 | Manual testing: leave `.phase1-complete` from a previous session, invoke Phase 2, verify it works correctly |
| Cleanup failure logs warning to stderr but does not block | Stop hook script | FR-7, NFR-2 | Code review: verify `rm` failures are caught with stderr warning |
| Concurrent release attempts: new invocation overwrites existing `.active` | Stop hook + SKILL.md | Edge Case 3 | Manual testing: write `.active` with plugin-A, invoke skill for plugin-B, verify `.active` now contains plugin-B |
| `.sdlc/releasing/` directory does not exist when hook fires | Stop hook script | Edge Case 4, FR-4.1 | Manual testing: ensure no `.sdlc/releasing/` directory, pipe JSON to hook, verify exit 0 (missing directory means missing `.active`) |

## Code Path Verification

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| FR-1 | State directory is `.sdlc/releasing/` | `stop-hook.sh`: `STATE_DIR=".sdlc/releasing"` | Code review | PASS |
| FR-2 | `.active` marker written at Phase 1 start with plugin name | `SKILL.md`: `echo "<plugin-name>" > .sdlc/releasing/.active` | Code review + manual test | PASS |
| FR-3 | `.phase1-complete` marker written after Phase 1 with PR number | `SKILL.md`: `echo "<pr-number>" > .sdlc/releasing/.phase1-complete` | Code review + manual test | PASS |
| FR-4.1 | No `.active` file -> exit 0 | `stop-hook.sh`: `if ! [[ -f "$STATE_DIR/.active" ]] 2>/dev/null; then exit 0; fi` | Pipe JSON to hook without `.active`, verify exit 0 | PASS |
| FR-4.2 | `.active` exists, no `.phase1-complete` -> check Phase 1 criteria | `stop-hook.sh`: existing Phase 1 pattern matching | Pipe JSON with `.active` present, verify Phase 1 logic runs | PASS |
| FR-4.3 | `.phase1-complete` exists -> exit 0 | `stop-hook.sh`: `if [[ -f "$STATE_DIR/.phase1-complete" ]] 2>/dev/null; then exit 0; fi` | Create both markers, pipe JSON, verify exit 0 | PASS |
| FR-4.4 | Phase 2 cleanup on success | `stop-hook.sh`: `rm -f "$STATE_DIR/.active" "$STATE_DIR/.phase1-complete"` | Create markers, pipe Phase 2 success JSON, verify markers removed | PASS |
| FR-5 | SKILL.md updated with marker operations at 4 lifecycle points | `SKILL.md`: Phase 1 start (`mkdir -p` + `echo > .active`), Phase 1 complete (`echo > .phase1-complete`), Phase 2 complete (`rm -rf .sdlc/releasing/`), cancellation (`rm -rf .sdlc/releasing/`) | Code review: verify all 4 points present; note Phase 2/cancellation use directory-level `rm -rf` while stop hook uses file-level `rm -f` | PASS |
| FR-6 | Keyword guard removed | `stop-hook.sh`: line 34 `grep -qE` block deleted | Code review + grep for removed pattern | PASS |
| FR-7 | Cleanup is idempotent and safe | `stop-hook.sh`: `rm -f` with error handling | Code review: verify `rm` uses `-f` flag and handles missing dir | PASS |
| NFR-1 | `stop_hook_active` bypass unchanged | `stop-hook.sh`: lines 24-28 | Code review: compare before/after | PASS |
| NFR-2 | Fail-open on I/O errors | `stop-hook.sh`: file checks use `2>/dev/null` | Code review: verify all file operations fail open | PASS |
| NFR-3 | State checks use pure bash file operations, no external commands for state decisions | `stop-hook.sh`: `[[ -f ... ]]` checks (not `cat`, `grep`, etc.) | Code review: confirm `.active`/`.phase1-complete` existence checks use only bash builtins | PASS |
| AC-1 | Stop hook uses both marker files | `stop-hook.sh` | Code review: verify `.active` and `.phase1-complete` references | PASS |
| AC-7 | SKILL.md has marker write/cleanup instructions | `SKILL.md` | Code review: verify instructions at all lifecycle points | PASS |
| AC-8 | Keyword guard removed | `stop-hook.sh` | Grep: no `release|version|bump|changelog` regex pattern | PASS |
| AC-9 | Fail-open on I/O errors | `stop-hook.sh` | Code review: verify `|| exit 0` on file operations | PASS |
| AC-10 | Cancellation instructions present | `SKILL.md` | Code review: verify cancellation section | PASS |

## Deliverable Verification

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| Updated stop hook script with state-file gates | Phase 1 | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | PASS |
| Updated SKILL.md with marker file instructions | Phase 2 | `.claude/skills/releasing-plugins/SKILL.md` | PASS |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N entries have corresponding test plan entries
- [x] All AC entries have corresponding test plan entries
- [x] NFR entries with testable criteria have corresponding entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for
- [x] New test recommendations are actionable and prioritized
