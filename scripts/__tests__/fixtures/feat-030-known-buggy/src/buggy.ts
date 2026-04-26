// Deliberately buggy production code for the FEAT-030 regression fixture.
// The exported function returns the wrong sign so the qa-buggy spec fails
// loudly. Do NOT fix this — the fixture exists to prove that executing-qa
// reports the bug (verdict ISSUES-FOUND) rather than patching it.
export function classifyNumber(n: number): 'positive' | 'negative' | 'zero' {
  if (n === 0) return 'zero';
  // BUG: signs inverted.
  if (n > 0) return 'negative';
  return 'positive';
}
