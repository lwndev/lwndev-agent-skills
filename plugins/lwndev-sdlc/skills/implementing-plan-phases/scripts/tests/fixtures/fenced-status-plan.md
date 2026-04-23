# Implementation Plan: Fenced-Status Fixture

## Overview

Fixture where `**Status:**` lines appear inside fenced code blocks. Scripts
must ignore the fenced occurrences and see only the real status line outside
the fence.

For reference, plans look like:

```
### Phase 99: Example Inside Fence
**Status:** Pending
**Status:** 🔄 In Progress
**Status:** ✅ Complete
```

## Recommended Build Sequence

### Phase 1: Real Phase

**Feature:** FEAT-XYZ
**Status:** Pending

Real content outside any fence.

Another fenced example inside this phase block:

```
**Status:** ✅ Complete
```

#### Deliverables

- [ ] `real.ts`

---

### Phase 2: Phase With Only Fenced Status

**Feature:** FEAT-XYZ

Demonstrates a phase block where the only `**Status:**` appearance is inside
a fenced block — the script must treat this phase as having no status.

```
**Status:** ✅ Complete
```

#### Deliverables

- [ ] `fenced-only.ts`

---
