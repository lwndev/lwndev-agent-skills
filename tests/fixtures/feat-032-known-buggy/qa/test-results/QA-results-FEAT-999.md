# QA Results: FEAT-999 (initial run)

**Verdict:** ISSUES-FOUND
**Tests:** 1 written, 1 failing
**Capability snapshot:** vitest

## Findings

### F1 — validateInput rejects whitespace-only input

**Severity:** error
**Source test:** `tests/unit/qa-input-validation.test.ts`

#### Reproduction

```typescript
// tests/unit/qa-input-validation.test.ts
import { describe, it, expect } from 'vitest';
import { validateInput } from '../../src/buggy-fn';

describe('validateInput (QA: whitespace edge)', () => {
  it('rejects whitespace-only input', () => {
    expect(validateInput('   ')).toBe(false);
  });
});
```

#### Observed

`validateInput('   ')` returns `true` (only the empty string is rejected).

#### Expected

`validateInput('   ')` returns `false` (whitespace-only input must be rejected
the same way the empty string is).
