# Implementation Plan: DAG Cycle Fixture

A 4-phase plan with a 2-cycle between phases 2 and 4. Used by
`validate-plan-dag.bats` cycle-detection tests.

## Recommended Build Sequence

### Phase 1: First

**Status:** Pending
**Depends on:** none

#### Deliverables

- [ ] `one.sh`

---

### Phase 2: Second

**Status:** Pending
**Depends on:** Phase 4

#### Deliverables

- [ ] `two.sh`

---

### Phase 3: Third

**Status:** Pending
**Depends on:** Phase 1

#### Deliverables

- [ ] `three.sh`

---

### Phase 4: Fourth

**Status:** Pending
**Depends on:** Phase 2

#### Deliverables

- [ ] `four.sh`
