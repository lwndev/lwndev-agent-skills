# Bug: Prompt Stop Hook JSON Failures

## Bug ID

`BUG-007`

## GitHub Issue

[#114](https://github.com/lwndev/lwndev-marketplace/issues/114)

## Category

`logic-error`

## Severity

`medium`

## Description

Prompt-based Stop hooks in `releasing-plugins`, `documenting-qa`, and `executing-qa` intermittently fail with `Stop hook error: JSON validation failed` because Haiku wraps its response in markdown code fences or adds explanatory text. The prior fix (issue #87, commit `24b5a8bc`) reduced frequency but did not eliminate the problem.

## Steps to Reproduce

1. Invoke `/releasing-plugins` and complete Phase 1 steps
2. When the Stop hook fires, Haiku evaluates the multi-criteria prompt
3. Intermittently, Haiku wraps its JSON response in markdown or adds explanatory text
4. Claude Code rejects the response: `Stop hook error: JSON validation failed`

This also reproduces with `/documenting-qa` and `/executing-qa` under the same conditions.

## Expected Behavior

Stop hooks should evaluate completion criteria deterministically and never produce JSON validation errors. The `orchestrating-workflows` skill demonstrates this with a command-based hook (`scripts/stop-hook.sh`) that uses exit codes and `jq` parsing — no LLM in the evaluation path.

## Actual Behavior

Haiku occasionally returns non-compliant responses despite the `"IMPORTANT: You must respond with ONLY a JSON object"` instruction. Example failure modes:
- Response wrapped in markdown code fences: `` ```json\n{"ok": true}\n``` ``
- Response prefixed with explanatory text: `Based on my analysis, {"ok": true}`
- Response includes trailing commentary after the JSON object

Claude Code's JSON parser rejects all of these, causing the Stop hook to error.

## Root Cause(s)

1. **No format enforcement mechanism for prompt hooks.** Prompt hooks (`type: "prompt"`) require the LLM to respond with `{"ok": true|false, "reason": "..."}` but provide no `output_json_schema` or structured-output mode. The prompt text is the only control over output shape, and LLM compliance is probabilistic, not guaranteed. This is a structural limitation — not a prompt-quality issue. See the current hook configurations in `.claude/skills/releasing-plugins/SKILL.md`, `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md`, and `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`.

2. **Complex multi-criteria prompts increase failure rate.** The `releasing-plugins` hook evaluates two release phases with multiple completion criteria per phase. The `executing-qa` hook evaluates two distinct phases (QA verification and documentation reconciliation). Complex prompts encourage Haiku to reason before answering, which produces preamble text that breaks JSON parsing.

3. **Prior fix is a mitigation, not a solution.** Commit `24b5a8bc` added `"IMPORTANT: You must respond with ONLY a JSON object — no markdown, no explanation, no wrapping. Just raw JSON."` to each prompt and condensed prompt text. This reduced but cannot eliminate failures because prompt-only constraints have no enforcement mechanism.

## Affected Files

- `.claude/skills/releasing-plugins/SKILL.md`
- `.claude/skills/releasing-plugins/scripts/stop-hook.sh` (new)
- `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md`
- `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` (new)
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` (new)
- `scripts/__tests__/documenting-qa.test.ts`
- `scripts/__tests__/executing-qa.test.ts`

## Acceptance Criteria

- [x] All three prompt-based Stop hooks replaced with `type: "command"` hooks that use shell scripts with exit codes (RC-1, RC-3)
- [x] Command hooks parse `last_assistant_message` with deterministic pattern matching — no LLM in the evaluation path (RC-1)
- [x] Each command hook correctly blocks stopping when its skill's completion criteria are not met (RC-2)
- [x] Each command hook correctly allows stopping when its skill's completion criteria are met (RC-2)
- [x] `stop_hook_active` bypass behavior preserved — hooks allow stop when the flag is set (RC-1)
- [x] No `Stop hook error: JSON validation failed` errors occur during normal skill execution (RC-1, RC-2, RC-3)

## Completion

**Status:** `Complete`

**Completed:** 2026-03-29

**Pull Request:** [#115](https://github.com/lwndev/lwndev-marketplace/pull/115)

## Notes

- The `orchestrating-workflows` skill already uses the command-based approach successfully (`plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/stop-hook.sh`). Borrow the structural pattern from this reference (command hook + exit codes 0/2), but note two differences: (1) the reference reads workflow-state files, whereas the new hooks must parse `last_assistant_message` from stdin JSON and use pattern matching to evaluate completion criteria; (2) the reference does not handle `stop_hook_active` — the new hooks must read this field from stdin JSON and exit 0 immediately when true, per the hooks guide.
- Prior art: Issue #87, commit `24b5a8bc`.
- Issue #114 recommends Option A (command hooks) as the fix. Option B (agent hooks) adds latency and still depends on LLM JSON compliance. Option C (simpler prompts) doesn't eliminate the structural problem.
