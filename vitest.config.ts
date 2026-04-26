import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    testMatch: ['**/__tests__/**/*.test.ts'],
    exclude: [
      '**/node_modules/**',
      '.claude/worktrees/**',
      // FEAT-030 known-buggy fixture: contents are deliberately failing
      // and exist only to be invoked by feat-030-executing-qa.test.ts via
      // a child vitest process pointed at the fixture's own config.
      'scripts/__tests__/fixtures/feat-030-known-buggy/**',
    ],
    fileParallelism: false,
    coverage: {
      include: ['scripts/**/*.ts'],
      exclude: ['scripts/**/__tests__/**'],
      reportsDirectory: 'coverage',
    },
  },
});
