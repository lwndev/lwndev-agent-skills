# Bug: Releasing Stop Hook False Positive After Phase Complete

## Bug ID

`BUG-008`

## Category

`logic-error`

## Severity

`medium`

## Description

The `releasing-plugins` stop hook produces a false positive block after Phase 1 is already complete, when the user performs an unrelated task (e.g., code review) in the same conversation. The hook only checks `last_assistant_message` for Phase 1 completion markers, so any subsequent non-release message triggers a spurious "Phase 1 is not complete" error.

## Steps to Reproduce

1. Invoke `/releasing-plugins` — complete Phase 1 (release PR created, user told to re-invoke for Phase 2)
2. Without ending the conversation, perform an unrelated task (e.g., `/review` a PR or answer a question)
3. The stop hook fires on the unrelated response
4. The hook checks `last_assistant_message` for "PR created" and "re-invoke/Phase 2" patterns
5. The unrelated message doesn't contain these markers → hook reports Phase 1 incomplete

## Expected Behavior

The stop hook should not block after Phase 1 is already complete. Once the release PR has been created and the user has been informed about Phase 2, subsequent unrelated messages should not trigger Phase 1 validation.

## Actual Behavior

```
Stop hook error: [bash .claude/skills/releasing-plugins/scripts/stop-hook.sh]:
Phase 1 is not complete. PR has not been created; user has not been told to re-invoke for Phase 2.
```

This occurs even though Phase 1 was fully completed earlier in the conversation.

## Root Cause(s)

1. The stop hook at `.claude/skills/releasing-plugins/scripts/stop-hook.sh:25-28` evaluates only `last_assistant_message` with no awareness of whether Phase 1 was already completed in an earlier message. The pattern matching at lines 38-48 requires both `HAS_PR` and `HAS_REINVOKE` to be true in the **current** message, but after Phase 1 completes, subsequent messages naturally won't contain these markers.

2. The stop hook has no state persistence mechanism — it cannot remember that Phase 1 was completed in a previous invocation. Each hook invocation is independent, making it impossible to distinguish "Phase 1 never started" from "Phase 1 completed, user moved on."

## Affected Files

- `.claude/skills/releasing-plugins/scripts/stop-hook.sh`

## Acceptance Criteria

- [ ] Stop hook does not block on non-release messages after Phase 1 is already complete (RC-1, RC-2)
- [ ] Stop hook still correctly blocks during Phase 1 when completion criteria are not met (RC-1)
- [ ] Stop hook still correctly blocks during Phase 2 when tag is not pushed (RC-1)
- [ ] Fix does not require changes to the Claude Code harness or hook input schema (RC-2)

## Completion

**Status:** `Completed`

**Completed:** 2026-04-04

**Pull Request:** [#124](https://github.com/lwndev/lwndev-marketplace/pull/124)

## Notes

- This is the same class of issue as BUG-007 (prompt-based stop hook failures) — stop hooks are stateless and only see the last message.
- The `documenting-qa` and `executing-qa` stop hooks may have similar vulnerability, though those skills tend not to have multi-phase workflows that span unrelated tasks.
- Possible fix approaches:
  - **Conversation-level state**: Write a marker file (e.g., `.sdlc/releasing/.phase1-complete`) when Phase 1 finishes, and check it in the hook. Clean up on Phase 2 completion.
  - **Pattern exclusion**: If the message doesn't contain any release-related keywords at all, treat it as a non-release message and allow stop (exit 0). This is lighter but could miss edge cases.
  - **Skill-scoped hooks**: If Claude Code adds support for hooks that only fire during skill invocations (not all stops), this class of bug goes away. Currently hooks fire on every stop.
