/**
 * The git-env sanitizer, with no side effects on import.
 *
 * Deliberately separate from `tests/setup/git-env.ts`, which is the Vitest
 * `setupFiles` entry point and DOES sanitize on import. Tests that want to
 * exercise the sanitizer must import it from here: importing the entry point
 * would run it, so an assertion like "this worker has no GIT_* vars" would
 * pass off its own import rather than off Vitest having registered the setup
 * file (issue #326).
 */

export const GIT_ENV_PREFIX = 'GIT_';

/**
 * Key `tests/setup/git-env.ts` stamps on `globalThis` once it has run.
 *
 * It lives in this module, not in the setup entry point, so a test can assert
 * the marker without importing — and thereby executing — the very module whose
 * execution it is trying to prove.
 */
export const GIT_ENV_SETUP_MARKER = '__gitEnvSetupRan__';

/**
 * Delete every GIT_* key from `env`, in place. Returns the removed key names
 * (sorted) so callers and tests can assert on what was stripped.
 */
export function stripGitEnv(env: NodeJS.ProcessEnv = process.env): string[] {
  const removed: string[] = [];
  for (const key of Object.keys(env)) {
    if (key.startsWith(GIT_ENV_PREFIX)) {
      delete env[key];
      removed.push(key);
    }
  }
  return removed.sort();
}
