/**
 * Environment for a child process spawned from inside a Vitest worker.
 *
 * Two independent reasons a test needs this, both learned the hard way:
 *
 *  1. A nested `vitest run` hangs if it inherits the parent suite's VITEST_*
 *     worker / thread / config hints.
 *  2. `run-framework.sh` matches vitest's summary line with
 *     `^[[:space:]]*Tests[[:space:]]+`. The parent suite leaves FORCE_COLOR
 *     set, which leaks into the child and turns that line into
 *     `\x1b[2m      Tests \x1b[22m …`, breaking the regex.
 *
 * Kept in one place because the two call sites drifting apart fails silently:
 * whichever copy misses a newly-leaking Vitest variable surfaces as an
 * unexplained multi-minute timeout, with nothing pointing at the env.
 */
export function childEnvWithoutVitest(base: NodeJS.ProcessEnv = process.env): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = { ...base };
  for (const key of Object.keys(env)) {
    if (key.startsWith('VITEST') || key === 'VITE_NODE_DEPS_MODULE_DIRECTORIES') {
      delete env[key];
    }
  }
  env.NO_COLOR = '1';
  env.FORCE_COLOR = '0';
  return env;
}
