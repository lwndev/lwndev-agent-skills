import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    testMatch: ['**/__tests__/**/*.test.ts', 'tests/unit/**/*.test.ts'],
    exclude: [
      '**/node_modules/**',
      '.claude/worktrees/**',
      // FEAT-030 known-buggy fixture: contents are deliberately failing
      // and exist only to be invoked by feat-030-executing-qa.test.ts via
      // a child vitest process pointed at the fixture's own config.
      'scripts/__tests__/fixtures/feat-030-known-buggy/**',
    ],
    fileParallelism: false,
    // Default 5000ms is too tight for execSync-heavy tests under full-suite
    // load (tsx cold-starts of release.ts / scaffold.ts / build.ts can
    // exceed it on a loaded machine).
    testTimeout: 15000,
    coverage: {
      include: ['scripts/**/*.ts'],
      exclude: ['scripts/**/__tests__/**'],
      reportsDirectory: 'coverage',
    },
  },
});
