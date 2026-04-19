<!--
Version history: version-1 artifacts have no frontmatter `version` field and
live unmodified under `qa/test-plans/QA-plan-*.md` (pre-redesign format). Any
parser MUST treat the absence of the `version` field as version 1. New runs
under the FEAT-018 redesign produce version 2 using this template.

This template is consumed by the documenting-qa skill (FR-4 / FR-9). The
stop hook at plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh
validates the structural rules below and refuses to allow a stop until the
artifact matches. Do NOT introduce `FR-\d+` references inside the
`## Scenarios (by dimension)` section — the stop hook enforces the no-spec
rule (FR-4) by grepping that section.
-->

---
id: FEAT-XXX
version: 2
timestamp: 2026-04-19T14:22:00Z
persona: qa
---

## User Summary

{2–5 sentences describing what the feature claims to do, in user-facing
terms. Built from the PR title/body or the `## User Story` section only —
NOT from the FR grid, ACs, or edge cases.}

## Capability Report

- Mode: test-framework | exploratory-only
- Framework: vitest | jest | pytest | go-test | none
- Package manager: npm | yarn | pnpm | none
- Test command: <string> | none
- Language: typescript | javascript | python | go | none

## Scenarios (by dimension)

Each scenario line MUST match the shape:

    - [P0|P1|P2] <description> | mode: test-framework|exploratory | expected: <test shape>

Every dimension heading MUST appear. A dimension with no scenarios MUST
either have at least one justification entry under
`## Non-applicable dimensions` OR have at least one scenario line — the
stop hook rejects the artifact otherwise.

### Inputs
- [P0] <description> | mode: test-framework | expected: <test shape>

### State transitions
- [P1] <description> | mode: test-framework | expected: <test shape>

### Environment
- [P1] <description> | mode: exploratory | expected: <test shape>

### Dependency failure
- [P2] <description> | mode: test-framework | expected: <test shape>

### Cross-cutting (a11y, i18n, concurrency, permissions)
- [P2] <description> | mode: exploratory | expected: <test shape>

## Non-applicable dimensions

- <dimension>: <justification for why this dimension does not apply to the
  change at hand>
