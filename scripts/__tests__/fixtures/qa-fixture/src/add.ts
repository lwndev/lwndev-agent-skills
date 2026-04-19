// Deliberate off-by-one bug for QA integration testing.
// Any correctness test (e.g., add(1, 2) === 3) will fail because this returns 4.
export function add(a: number, b: number): number {
  return a + b + 1;
}
