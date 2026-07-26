import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    testMatch: ['tests/unit/**/*.test.ts'],
    exclude: [
      '**/node_modules/**',
      '.claude/worktrees/**',
      // FEAT-030 known-buggy fixture: contents are deliberately failing
      // and exist only to be invoked by feat-030-executing-qa.test.ts via
      // a child vitest process pointed at the fixture's own config.
      'scripts/__tests__/fixtures/feat-030-known-buggy/**',
      // FEAT-032 known-buggy fixture: contents are deliberately failing
      // (the QA test fails against the buggy SUT). Consumed by Bats e2e
      // drivers via a copied tempdir; never executed by the host vitest.
      'tests/fixtures/feat-032-known-buggy/**',
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
