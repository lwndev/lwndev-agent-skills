# Feature Requirements: FEAT-028 Test Fixture

## Overview
Minimal feature-requirement fixture used by `init-workflow.bats` to exercise the
`extract-issue-ref.sh` call path on a feature artifact. Content is intentionally
minimal; only the filename-embedded `FEAT-028` prefix and the `## GitHub Issue`
section are load-bearing.

## Feature ID
`FEAT-028`

## GitHub Issue
[#186](https://github.com/lwndev/lwndev-marketplace/issues/186)

## Priority
Medium

## User Story
As a test fixture, I need to exist so that `init-workflow.sh` has a real file to
hand to `extract-issue-ref.sh`.

## Functional Requirements
- **FR-1:** The fixture filename begins with `FEAT-028` so the TYPE-prefix regex
  in `init-workflow.sh` succeeds.
- **FR-2:** The `## GitHub Issue` section supplies `#186` for the non-empty
  `issueRef` graceful-path test.
