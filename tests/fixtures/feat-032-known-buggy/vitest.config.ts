// Minimal plain-object vitest config. Mirrors qa-fixture/vitest.config.ts so
// the fixture remains loadable when copied into a tempdir without a local
// node_modules. Integration tests point vitest at this config explicitly.
export default {
  test: {
    include: ['tests/**/*.{spec,test}.{ts,js}'],
  },
};
