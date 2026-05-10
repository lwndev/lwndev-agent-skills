// Peer test for src/buggy-fn.ts. Exercises only the cases the original spec
// called out (happy path + empty-string) so this file passes against the bug.
// The adopt phase moves tests/unit/qa-input-validation.test.ts to
// tests/unit/buggy-fn.qa.test.ts as a sibling next to this file.
import { describe, it, expect } from 'vitest';
import { validateInput } from '../../src/buggy-fn';

describe('validateInput', () => {
  it('accepts a non-empty string', () => {
    expect(validateInput('hello')).toBe(true);
  });
  it('rejects the empty string', () => {
    expect(validateInput('')).toBe(false);
  });
});
