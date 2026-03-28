# QA Test Plan: QA Skill Audits Coverage Instead of Executing Test Plan

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-BUG-003 |
| **Requirement Type** | BUG |
| **Requirement ID** | BUG-003 |
| **Source Documents** | `requirements/bugs/BUG-003-qa-coverage-auditor-not-executor.md` |
| **Date Created** | 2026-03-28 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/qa-verifier.test.ts` | Agent definition structure, frontmatter, tools, verification responsibilities | PENDING |
| `scripts/__tests__/executing-qa.test.ts` | Skill definition, frontmatter, allowed-tools, stop hook, test results template, validation API | PENDING |
| `scripts/__tests__/documenting-qa.test.ts` | Documenting-qa skill (should not be affected by this fix) | PENDING |
| `scripts/__tests__/build.test.ts` | Build/validation pipeline (should not be affected by this fix) | PENDING |

## Code Path Verification

Traceability from root causes to implementation:

| Requirement | Description | Expected Code Path | Verification Method |
|-------------|-------------|-------------------|-------------------|
| RC-1 | qa-verifier agent was architected as a test runner/coverage auditor — all 4 steps revolved around `npm test` and test coverage (pre-fix lines 29, 37, 43, 62) | `plugins/lwndev-sdlc/agents/qa-verifier.md` | Read the file and confirm: (a) Step 1 no longer mandates `npm test` as the first action, (b) Steps are reoriented toward direct condition verification, (c) Coverage auditing is removed or demoted to a secondary role |
| RC-2 | executing-qa skill delegated entirely to qa-verifier without direct verification of test plan entries (pre-fix lines 72-75) | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | Read the file and confirm: (a) The verification loop iterates through test plan entries, (b) Each entry is directly verified rather than delegated for coverage audit, (c) The skill instructs direct verification methods (reading files, running commands, checking behavior) |
| RC-3 | Auto-fix instructions defined developer activities: writing tests, fixing tests, addressing coverage gaps (pre-fix lines 81-85) | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | Read the file and confirm: (a) Auto-fix instructions no longer say "write missing tests", "fix broken tests", or "address coverage gaps", (b) Fix actions are reframed around addressing failed verification entries (e.g., fixing code that causes a FAIL, not writing tests) |

## Acceptance Criteria Verification

| AC # | Acceptance Criterion | RC Ref | Verification Method | Expected Result |
|------|---------------------|--------|-------------------|-----------------|
| AC-1 | The `executing-qa` skill iterates through each entry in the test plan and directly verifies the condition described | RC-2, RC-3 | Read `SKILL.md` Step 2 and confirm it describes iterating test plan entries and verifying each condition directly | The verification loop section describes entry-by-entry iteration with direct verification (read file, run command, check behavior) rather than delegating to a coverage auditor |
| AC-2 | Each test plan entry gets a discrete PASS/FAIL result based on direct verification, not automated test existence | RC-1, RC-2 | Read both `qa-verifier.md` and `SKILL.md` and confirm the verification model produces per-entry PASS/FAIL from direct checks | The agent/skill describes recording PASS/FAIL per test plan entry based on whether the described condition holds, not whether an automated test exists |
| AC-3 | The qa-verifier agent (or replacement) acts as a direct verification engine | RC-1 | Read `qa-verifier.md` and confirm its responsibilities and process describe direct condition verification | The agent's process steps describe reading files, checking conditions, running targeted commands — not running `npm test` and auditing coverage |
| AC-4 | QA results document records per-entry PASS/FAIL outcomes from direct verification | RC-2, RC-3 | Read `test-results-template.md` and confirm it has a section for per-entry PASS/FAIL results from direct verification | The template includes a table or section where each test plan entry has a discrete PASS/FAIL outcome with verification evidence |
| AC-5 | Running `npm test` may still occur but is not the primary verification mechanism | RC-1 | Read `qa-verifier.md` and confirm `npm test` is mentioned as optional/secondary, not as Step 1 | `npm test` is either absent or described as one optional input alongside direct verification, not the primary or first step |

## Reproduction Step Verification

Confirm the bug no longer reproduces after the fix:

| Step | Verification Method | Expected Result |
|------|-------------------|-----------------|
| The qa-verifier agent's Step 1 is no longer "Run `npm test`" | Read `plugins/lwndev-sdlc/agents/qa-verifier.md` and check the first step in the verification process | Step 1 describes a direct verification action (e.g., iterate test plan entries), not running the test suite |
| The executing-qa skill no longer instructs "run the full test suite, check coverage" in its delegation block | Read `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` lines 72-75 area and check the subagent instructions | Delegation instructions (if subagent is still used) describe direct verification of test plan entries, not coverage auditing |
| The auto-fix loop no longer writes automated tests to fill coverage gaps | Read `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` auto-fix section and check the fix instructions | Fix instructions address failed verification entries (e.g., fix the code or configuration that caused a FAIL), not write/fix automated tests |

## Deliverable Verification

| Deliverable | Description | Expected Path | Exists |
|-------------|-------------|---------------|--------|
| Updated qa-verifier agent | Reoriented from coverage auditor to direct verification engine | `plugins/lwndev-sdlc/agents/qa-verifier.md` | PENDING |
| Updated executing-qa skill | Verification loop iterates test plan entries with direct verification | `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` | PENDING |
| Updated test results template | Supports per-entry PASS/FAIL from direct verification | `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template.md` | PENDING |

## Verification Checklist

- [ ] All existing tests pass (regression baseline)
- [ ] All RC-N entries have corresponding test plan entries
- [ ] All AC entries have corresponding verification methods
- [ ] Reproduction steps are verified as no longer reproducible
- [ ] Deliverable files exist and reflect the fix
- [ ] Coverage gaps are identified with recommendations
- [ ] Code paths trace from requirements to implementation
