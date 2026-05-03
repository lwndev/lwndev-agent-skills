# Implementation Plan: DAG Fenced Fixture

Plan with one `**Depends on:**` reference inside a fenced code block (which
must be ignored) and a real one outside fences (which must be parsed).
Used by `validate-plan-dag.bats` fence-awareness test.

## Recommended Build Sequence

### Phase 1: Foundation

**Status:** Pending

Template documentation showing the dependency line shape:

```
**Depends on:** Phase 99
```

The fenced reference above must NOT be treated as a real dependency.

#### Deliverables

- [ ] `one.sh`

---

### Phase 2: Builds On Foundation

**Status:** Pending
**Depends on:** Phase 1

#### Deliverables

- [ ] `two.sh`
