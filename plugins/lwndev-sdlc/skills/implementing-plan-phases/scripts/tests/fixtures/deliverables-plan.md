# Implementation Plan: Deliverables Fixture

## Overview

Fixture for FR-3 `check-deliverable.sh` bats tests. Exercises:
- A phase with exactly three deliverables (index-dispatch tests).
- A phase containing a fenced code block with `- [ ]` lines that MUST NOT be flipped.
- A phase with two unchecked deliverables sharing a common substring (ambiguity tests).
- A cross-phase deliverable (phase-scoping test).

## Recommended Build Sequence

### Phase 1: Three Deliverables

**Feature:** FEAT-XYZ
**Status:** Pending

#### Rationale

Three deliverables: one already checked, two unchecked. Used for numeric index
dispatch.

#### Deliverables

- [x] `scripts/alpha.sh` - First deliverable, already checked
- [ ] `scripts/beta.sh` - Second deliverable, unchecked
- [ ] `scripts/gamma.sh` - Third deliverable, unchecked

---

### Phase 2: Fence-Protected Deliverables

**Feature:** FEAT-XYZ
**Status:** Pending

#### Rationale

Example templates live in a fenced block; they MUST NOT be treated as real
deliverables.

Example of a generic deliverable line template:

```
- [ ] `fenced-template.ts` - Not a real deliverable, lives inside a fence
- [ ] `another-fenced.ts` - Also fenced, must not be flipped
```

#### Deliverables

- [ ] `scripts/delta.sh` - Real deliverable outside the fence

---

### Phase 3: Ambiguous Substrings

**Feature:** FEAT-XYZ
**Status:** Pending

#### Rationale

Two unchecked deliverables share the substring `parser` for ambiguity tests.

#### Deliverables

- [ ] `scripts/json-parser.sh` - Ambiguous-substring deliverable one
- [ ] `scripts/yaml-parser.sh` - Ambiguous-substring deliverable two
- [x] `scripts/toml-parser.sh` - Already-checked match (should be ignored for ambiguity)

---

### Phase 4: Single Deliverable in Other Phase

**Feature:** FEAT-XYZ
**Status:** Pending

#### Rationale

Used to verify that a substring matching this phase's deliverable is NOT
flipped when the caller targets a different phase number.

#### Deliverables

- [ ] `scripts/phase-four-only.sh` - Only exists in phase 4

---
