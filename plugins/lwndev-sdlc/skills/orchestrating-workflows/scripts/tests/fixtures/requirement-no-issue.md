# Feature Requirements: FEAT-028 No-Issue Fixture

## Overview
Fixture with no `## GitHub Issue`, `## Issue`, or `## Issue Tracker` section.
Used by the graceful-degradation path in `init-workflow.bats` to verify
`issueRef` resolves to an empty string when the document lacks a recognised
issue section.

## Feature ID
`FEAT-028`

## Priority
Medium

## User Story
Used as a negative test fixture — exercises the non-fatal empty-issue-ref
graceful path.
