// Minimal plain-object vitest config (no import from 'vitest/config' so this
// file remains loadable when the fixture is copied into a tempdir that has no
// node_modules of its own — the integration test points vitest at this
// config explicitly).
export default {
  test: {
    include: ['__tests__/**/*.{spec,test}.{ts,js}'],
  },
};
