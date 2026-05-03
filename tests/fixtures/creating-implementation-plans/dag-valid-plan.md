# Implementation Plan: DAG Valid Fixture

Synthetic plan used by `validate-plan-dag.bats` happy-path tests. Three
phases form a clean DAG:

```
Phase 1 (no deps)
  ↑
Phase 2 (depends on 1)
  ↑
Phase 3 (depends on 1, 2)
```

## Recommended Build Sequence

### Phase 1: First

**Status:** Pending
**Depends on:** none

#### Implementation Steps

1. Step one.

#### Deliverables

- [ ] `path/one.sh`

---

### Phase 2: Second

**Status:** Pending
**Depends on:** Phase 1

#### Implementation Steps

1. Step one.

#### Deliverables

- [ ] `path/two.sh`

---

### Phase 3: Third

**Status:** Pending
**Depends on:** Phase 1, Phase 2

#### Implementation Steps

1. Step one.

#### Deliverables

- [ ] `path/three.sh`
