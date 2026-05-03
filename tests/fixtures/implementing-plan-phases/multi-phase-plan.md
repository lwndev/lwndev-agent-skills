# Implementation Plan: Multi-Phase Fixture

## Overview

Four-phase fixture with mixed statuses and an explicit Depends-on line.

## Recommended Build Sequence

### Phase 1: Alpha

**Feature:** FEAT-XYZ
**Status:** ✅ Complete

#### Deliverables

- [x] `a.ts`

---

### Phase 2: Beta

**Feature:** FEAT-XYZ
**Status:** 🔄 In Progress

#### Deliverables

- [ ] `b.ts`

---

### Phase 3: Gamma

**Feature:** FEAT-XYZ
**Status:** Pending
**Depends on:** Phase 2

#### Deliverables

- [ ] `c.ts`

---

### Phase 4: Delta

**Feature:** FEAT-XYZ
**Status:** Pending

#### Deliverables

- [ ] `d.ts`

---
