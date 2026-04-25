# Implementation Plan: Split Overflow Fixture

Used by `split-phase-suggest.bats` to exercise the 3-way split path on a
9-step phase. Step 6 carries an explicit `Depends on Step 4` annotation so
the constraint logic must keep step 4 and step 6 in the same chunk (or step
6 in a later chunk than step 4 — the constraint only forbids a chunk that
ends between them while owning step 4).

## Recommended Build Sequence

### Phase 1: Big Phase

**Status:** Pending

#### Implementation Steps

1. Lay groundwork.
2. Wire scaffolding.
3. Add unit primitives.
4. Land core function.
5. Cover happy path.
6. Wire integration test (Depends on Step 4).
7. Run regression suite.
8. Update docs.
9. Final review.

#### Deliverables

- [ ] `plugins/example/scripts/big-phase.sh`
- [ ] `plugins/example/scripts/tests/big-phase.bats`
