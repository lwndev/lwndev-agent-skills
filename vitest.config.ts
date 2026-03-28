import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    testMatch: ['**/__tests__/**/*.test.ts'],
    fileParallelism: false,
    coverage: {
      include: ['scripts/**/*.ts'],
      exclude: ['scripts/**/__tests__/**'],
      reportsDirectory: 'coverage',
    },
  },
});
