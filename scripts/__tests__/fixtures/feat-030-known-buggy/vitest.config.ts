// Plain-object vitest config so the fixture remains loadable without a local
// node_modules — the regression test points the root vitest binary at this
// config explicitly (mirrors scripts/__tests__/fixtures/qa-fixture).
export default {
  test: {
    include: ['__tests__/**/*.{spec,test}.{ts,js}'],
  },
};
