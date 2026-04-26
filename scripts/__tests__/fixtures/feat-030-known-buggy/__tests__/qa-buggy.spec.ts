// FEAT-030 regression fixture — adversarial correctness test against the
// classifyNumber() API. The production code in src/buggy.ts inverts the
// sign, so these assertions are expected to fail. Failures are the
// fixture's whole point: executing-qa must report ISSUES-FOUND, not patch.
import { describe, it, expect } from 'vitest';
import { classifyNumber } from '../src/buggy';

describe('qa-inputs: classifyNumber correctness', () => {
  it('classifyNumber(5) should equal positive', () => {
    expect(classifyNumber(5)).toBe('positive');
  });

  it('classifyNumber(-3) should equal negative', () => {
    expect(classifyNumber(-3)).toBe('negative');
  });
});
