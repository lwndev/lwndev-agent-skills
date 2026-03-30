# QA Test Plan: Prompt Stop Hook JSON Failures

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-BUG-007 |
| **Requirement Type** | BUG |
| **Requirement ID** | BUG-007 |
| **Source Documents** | `requirements/bugs/BUG-007-prompt-stop-hook-json-failures.md` |
| **Date Created** | 2026-03-29 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/documenting-qa.test.ts` | Validates documenting-qa SKILL.md structure including Stop hook config | PASS |
| `scripts/__tests__/executing-qa.test.ts` | Validates executing-qa SKILL.md structure including Stop hook config | PASS |
| `scripts/__tests__/orchestrating-workflows.test.ts` | Validates orchestrating-workflows command-based Stop hook and stop-hook.sh script | PASS |
| `scripts/__tests__/build.test.ts` | Plugin validation pipeline | PASS |

**Note:** The `documenting-qa.test.ts` and `executing-qa.test.ts` tests currently assert `type: prompt` for the Stop hook (lines 102-105 and 103-105 respectively). These assertions will need to be updated to `type: command` as part of the fix. The `orchestrating-workflows.test.ts` tests already validate the command-based pattern and serve as the model for the updated tests.

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| Verify documenting-qa SKILL.md uses `type: command` Stop hook | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` | RC-1, AC-1 | High | PASS |
| Verify executing-qa SKILL.md uses `type: command` Stop hook | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | RC-1, AC-1 | High | PASS |
| Verify releasing-plugins SKILL.md uses `type: command` Stop hook | `.claude/skills/releasing-plugins/SKILL.md` | RC-1, AC-1 | High | PASS |
| Verify documenting-qa stop-hook.sh exists and is executable | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` | AC-1, AC-2 | High | PASS |
| Verify executing-qa stop-hook.sh exists and is executable | `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` | AC-1, AC-2 | High | PASS |
| Verify releasing-plugins stop-hook.sh exists and is executable | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | AC-1, AC-2 | High | PASS |
| Verify each stop-hook.sh reads `stop_hook_active` from stdin JSON and exits 0 when true | All three scripts | AC-5, RC-1 | High | PASS |
| Verify each stop-hook.sh reads `last_assistant_message` from stdin JSON | All three scripts | AC-2, RC-1 | High | PASS |
| Verify documenting-qa stop-hook.sh blocks when plan is incomplete | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` | AC-3, RC-2 | High | PASS |
| Verify documenting-qa stop-hook.sh allows when plan is complete | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` | AC-4, RC-2 | High | PASS |
| Verify executing-qa stop-hook.sh blocks when QA is incomplete | `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` | AC-3, RC-2 | High | PASS |
| Verify executing-qa stop-hook.sh allows when QA is complete | `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` | AC-4, RC-2 | High | PASS |
| Verify releasing-plugins stop-hook.sh blocks when release phase is incomplete | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | AC-3, RC-2 | High | PASS |
| Verify releasing-plugins stop-hook.sh allows when release phase is complete | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | AC-4, RC-2 | High | PASS |
| Verify no `type: prompt` Stop hooks remain in any affected SKILL.md | All three SKILL.md files | AC-1, AC-6, RC-3 | High | PASS |
| Verify no `model: haiku` in Stop hook frontmatter of affected skills | All three SKILL.md files | AC-1, RC-1 | Medium | PASS |
| Update documenting-qa.test.ts assertions from `type: prompt` to `type: command` | `scripts/__tests__/documenting-qa.test.ts` | AC-1 | High | PASS |
| Update executing-qa.test.ts assertions from `type: prompt` to `type: command` | `scripts/__tests__/executing-qa.test.ts` | AC-1 | High | PASS |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| No existing tests for releasing-plugins SKILL.md structure or Stop hook | `.claude/skills/releasing-plugins/SKILL.md` | AC-1, AC-6 | Manual verify — releasing-plugins is outside the plugin validation pipeline |
| No integration test for stop-hook.sh scripts with piped JSON stdin | All three new scripts | AC-2, AC-3, AC-4, AC-5 | Write shell-level tests or verify via manual `echo '{"stop_hook_active": true}' | bash script.sh` invocations during QA execution |
| Edge case: malformed or empty stdin JSON | All three new scripts | AC-6 | Verify scripts handle gracefully (exit 0 to avoid trapping user) |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| RC-1 | No format enforcement for prompt hooks — replace with command hooks | SKILL.md frontmatter `type: prompt` → `type: command` with `command:` pointing to script | Code review + automated test | PASS |
| RC-2 | Complex multi-criteria prompts — move evaluation logic to shell pattern matching | Each stop-hook.sh: parse `last_assistant_message`, grep for completion indicators | Code review + manual shell test | PASS |
| RC-3 | Prior fix is mitigation only — full replacement eliminates the class of bug | Remove `IMPORTANT: You must respond with ONLY a JSON object` prompts entirely from frontmatter | Code review + grep verification | PASS |
| AC-1 | All three prompt hooks replaced with command hooks | Frontmatter contains `type: command` and `command:` path, no `type: prompt` | Automated test | PASS |
| AC-2 | Command hooks parse `last_assistant_message` deterministically | Each script reads stdin JSON via `jq`, extracts `.last_assistant_message`, uses grep/pattern matching | Code review + manual test | PASS |
| AC-3 | Hooks block stopping when criteria not met | Script exits 2 with stderr message when patterns not found | Manual shell test with incomplete message | PASS |
| AC-4 | Hooks allow stopping when criteria met | Script exits 0 when completion patterns found | Manual shell test with complete message | PASS |
| AC-5 | `stop_hook_active` bypass preserved | Script checks `.stop_hook_active` from stdin JSON; exits 0 when true | Manual shell test with `{"stop_hook_active": true}` | PASS |
| AC-6 | No JSON validation errors during execution | No `type: prompt` hooks remain; command hooks use exit codes only | Grep for `type: prompt` in affected files + full test suite pass | PASS |

## Deliverable Verification

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| documenting-qa command Stop hook script | Bug fix | `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` | PASS |
| executing-qa command Stop hook script | Bug fix | `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` | PASS |
| releasing-plugins command Stop hook script | Bug fix | `.claude/skills/releasing-plugins/scripts/stop-hook.sh` | PASS |
| Updated documenting-qa SKILL.md frontmatter | Bug fix | `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` | PASS |
| Updated executing-qa SKILL.md frontmatter | Bug fix | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | PASS |
| Updated releasing-plugins SKILL.md frontmatter | Bug fix | `.claude/skills/releasing-plugins/SKILL.md` | PASS |
| Updated documenting-qa test assertions | Bug fix | `scripts/__tests__/documenting-qa.test.ts` | PASS |
| Updated executing-qa test assertions | Bug fix | `scripts/__tests__/executing-qa.test.ts` | PASS |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
