// Known-buggy production file for FEAT-032 NFR-4 end-to-end fixture.
//
// The bug: validateInput rejects the empty string but does NOT reject the
// whitespace-only string. The peer test (buggy-fn.test.ts) only covers the
// happy path and the empty-string path, so it passes against the bug. The
// QA-authored test (qa-input-validation.test.ts) exercises the whitespace
// edge and fails until the production fix lands.
//
// The "fix" applied during the e2e test is a one-line change that trims the
// input before the empty-check.
export function validateInput(s: string): boolean {
  if (s === '') return false;
  return true;
}
