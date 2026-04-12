import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    testMatch: ['**/__tests__/**/*.test.ts'],
    exclude: ['**/node_modules/**', '.claude/worktrees/**'],
    fileParallelism: false,
    coverage: {
      include: ['scripts/**/*.ts'],
      exclude: ['scripts/**/__tests__/**'],
      reportsDirectory: 'coverage',
    },
  },
});
