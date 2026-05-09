// QA-authored test for FEAT-032 NFR-4 end-to-end fixture.
//
// This test imports the same SUT as buggy-fn.test.ts so adopt-qa-test.sh's
// SUT-resolution heuristic locates the peer test deterministically. The
// fixture's adopt phase moves this file to tests/unit/buggy-fn.qa.test.ts.
import { describe, it, expect } from 'vitest';
import { validateInput } from '../../src/buggy-fn';

describe('validateInput (QA: whitespace edge)', () => {
  it('rejects whitespace-only input', () => {
    expect(validateInput('   ')).toBe(false);
  });
});
