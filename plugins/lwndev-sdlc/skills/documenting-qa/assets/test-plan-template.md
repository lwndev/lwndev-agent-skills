# QA Test Plan: [Brief Title]

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-{id} |
| **Requirement Type** | FEAT / CHORE / BUG |
| **Requirement ID** | {ID} |
| **Source Documents** | <!-- List all source docs: requirements doc, implementation plan, etc. --> |
| **Date Created** | YYYY-MM-DD |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| <!-- path/to/test --> | <!-- what it tests --> | <!-- PASS / FAIL / PENDING --> |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| <!-- what to test --> | <!-- file(s) under test --> | <!-- FR-N / RC-N / AC --> | <!-- High / Medium / Low --> | -- |

## Coverage Gap Analysis

Code paths and functionality that lack test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| <!-- what's missing --> | <!-- file:function --> | <!-- FR-N / RC-N / AC --> | <!-- write unit test / integration test / manual verify --> |

## Code Path Verification

Traceability from requirements to implementation:

<!-- For FEAT: one entry per FR-N -->
<!-- For BUG: one entry per RC-N -->
<!-- For CHORE: one entry per AC -->

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| <!-- FR-N / RC-N / AC --> | <!-- what it requires --> | <!-- file:function or code area --> | <!-- automated test / code review / manual --> | -- |

## Deliverable Verification

<!-- For FEAT with implementation plan: one entry per phase deliverable -->
<!-- For CHORE/BUG: list key output artifacts -->

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| <!-- deliverable name --> | <!-- Phase N --> | <!-- expected file path --> | -- |

## Plan Completeness Checklist

- [ ] All existing tests pass (regression baseline)
- [ ] All FR-N / RC-N / AC entries have corresponding test plan entries
- [ ] Coverage gaps are identified with recommendations
- [ ] Code paths trace from requirements to implementation
- [ ] Phase deliverables are accounted for (if applicable)
- [ ] New test recommendations are actionable and prioritized
