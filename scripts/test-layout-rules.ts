/**
 * Shared rule module for the test layout validator (FR-9) and the PreToolUse
 * enforcement hook (FR-10). Both tools import from this module so the rule IDs
 * and the allow-rule never diverge (Edge Case 5).
 */

export const RULE_TS_OUTSIDE_TESTS_UNIT = 'ts-outside-tests-unit';
export const RULE_SPEC_EXTENSION_DISALLOWED = 'spec-extension-disallowed';
export const RULE_BATS_OUTSIDE_TESTS_BATS = 'bats-outside-tests-bats';

/**
 * Canonical destinations per rule. Surfaced in hook rejection messages so the
 * model can self-correct without re-reading the spec.
 */
export const CANONICAL_DESTINATIONS: Readonly<Record<string, string>> = {
  [RULE_TS_OUTSIDE_TESTS_UNIT]: 'tests/unit/',
  [RULE_SPEC_EXTENSION_DISALLOWED]: 'tests/unit/ (rename .spec.ts to .test.ts)',
  [RULE_BATS_OUTSIDE_TESTS_BATS]: 'tests/bats/',
};

/**
 * Allow-rule paths. The single allowed exception is the FEAT-030 known-buggy
 * fixture, which is invoked as a child Vitest process by its harness and must
 * stay at its existing path.
 *
 * Paths are repo-root-relative and use forward slashes regardless of platform.
 */
export const ALLOWED_FIXTURE_PATHS: readonly string[] = [
  'scripts/__tests__/fixtures/feat-030-known-buggy/__tests__/qa-buggy.spec.ts',
];

/**
 * Test root prefixes (repo-root-relative, with trailing slash). Matched against
 * normalized paths, so a path is considered "under" a root iff it starts with
 * the prefix.
 */
const TESTS_UNIT_PREFIX = 'tests/unit/';
const TESTS_BATS_PREFIX = 'tests/bats/';

export interface ClassifyResult {
  rule: string;
}

/**
 * Normalize a path to repo-root-relative POSIX form. Strips a leading "./" and
 * converts back-slashes to forward-slashes so the classifier behaves the same
 * way on macOS, Linux, and Windows hooks.
 */
function normalize(filePath: string): string {
  let p = filePath.replace(/\\/g, '/');
  while (p.startsWith('./')) {
    p = p.slice(2);
  }
  return p;
}

/**
 * Classify a path against the layout rules.
 *
 * Returns the rule that fired, or `null` if the path is allowed (either it is
 * not a test file extension, it lives at its canonical leaf, or it is in the
 * `ALLOWED_FIXTURE_PATHS` list).
 *
 * The classifier short-circuits on non-test extensions so it is safe to call
 * from the PreToolUse hot path on every Write/Edit.
 */
export function classifyPath(filePath: string): ClassifyResult | null {
  if (!filePath) return null;
  const p = normalize(filePath);

  // Allow-rule short-circuit: explicit allow always wins.
  if (ALLOWED_FIXTURE_PATHS.includes(p)) {
    return null;
  }

  // .spec.ts is disallowed everywhere except the allow-rule above.
  if (p.endsWith('.spec.ts')) {
    return { rule: RULE_SPEC_EXTENSION_DISALLOWED };
  }

  // .test.ts must live under tests/unit/.
  if (p.endsWith('.test.ts')) {
    if (p.startsWith(TESTS_UNIT_PREFIX)) {
      return null;
    }
    return { rule: RULE_TS_OUTSIDE_TESTS_UNIT };
  }

  // .bats must live under tests/bats/.
  if (p.endsWith('.bats')) {
    if (p.startsWith(TESTS_BATS_PREFIX)) {
      return null;
    }
    return { rule: RULE_BATS_OUTSIDE_TESTS_BATS };
  }

  // Non-test path: no rule fires.
  return null;
}
