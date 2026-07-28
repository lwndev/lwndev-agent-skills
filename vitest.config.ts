import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // `include`, not `testMatch` — Vitest has no `testMatch` option, so the
    // previous spelling was a silent no-op and the default `**/*.test.ts` glob
    // collected everything, leaving the `exclude` entries below as the only
    // thing keeping deliberately-failing fixtures out of the host suite.
    //
    // The extension set is deliberately wider than the repo's current habit.
    // scripts/test-layout-rules.ts only constrains `.spec.ts`, `.test.ts` and
    // `.bats`, so a `tests/unit/foo.test.tsx` (or `.mts`, `.cts`, `.jsx`) is
    // accepted by `npm run validate` and by the PreToolUse layout hook. If the
    // include glob did not match it, `npm test` would report all-green having
    // executed none of its assertions — the two definitions of "where a test
    // may live" would disagree, and disagree by failing OPEN. `.test.js` is in
    // the set for the same reason: CLAUDE.md names `tests/unit/qa-*.test.js` as
    // a canonical QA-phase file class.
    include: ['tests/unit/**/*.test.{ts,tsx,mts,cts,js,jsx,mjs,cjs}'],
    exclude: [
      // Must stay: setting `exclude` at all overrides Vitest's defaults.
      '**/node_modules/**',
      // Both known-buggy fixture trees (scripts/__tests__/fixtures/
      // feat-030-known-buggy/ and tests/fixtures/feat-032-known-buggy/) used to
      // be listed here. The include glob is anchored at tests/unit/, so it
      // cannot reach either of them and the entries were dead — misleading a
      // reader into thinking `exclude` is what holds the deliberately-failing
      // fixtures out of the host suite. The same reasoning retires the old
      // '.claude/worktrees/**' entry.
    ],
    // Strips inherited GIT_* env vars in every worker so fixture git calls can
    // never target the real repository (issue #326).
    setupFiles: ['tests/setup/git-env.ts'],
    fileParallelism: true,
    // Default 5000ms is too tight for execSync-heavy tests under full-suite
    // load (tsx cold-starts of release.ts / scaffold.ts / build.ts can
    // exceed it on a loaded machine).
    testTimeout: 15000,
    coverage: {
      include: ['scripts/**/*.ts'],
      exclude: [
        'tests/**',
        '**/*.test.ts',
        'scripts/__tests__/fixtures/feat-030-known-buggy/**',
        'tests/fixtures/feat-032-known-buggy/**',
      ],
      reportsDirectory: 'coverage',
    },
  },
});
