/**
 * Vitest setup file: strip inherited git environment.
 *
 * An inherited GIT_DIR redirects every child `git` call at the real repository
 * regardless of the `cwd` a test passes. See the "Tests must never inherit git
 * environment" bullet in CLAUDE.md for the full failure mode (issue #326).
 *
 * Registered as `setupFiles` in vitest.config.ts, so it runs in every worker
 * before every test file. Tests that build their own child env from
 * `process.env` inherit the sanitized copy for free.
 */

export const GIT_ENV_PREFIX = 'GIT_';

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

stripGitEnv(process.env);
