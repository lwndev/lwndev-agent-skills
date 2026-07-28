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
 *
 * The sanitizer itself lives in `./strip-git-env` so tests can import it
 * without triggering this module's side effect. Importing THIS module runs the
 * sanitization; that is the point, and it is why nothing else should import it.
 */

import { stripGitEnv, GIT_ENV_SETUP_MARKER } from './strip-git-env';

// The marker proves this module ran as a registered setup file rather than as
// an incidental import. A wiring assertion that only checks `process.env` is
// self-satisfying; one that checks the marker fails if a config migration
// (e.g. moving to Vitest `projects:`, whose per-project `test` block does not
// inherit root `test.setupFiles`) keeps the config text but loses the effect.
stripGitEnv(process.env);
(globalThis as Record<string, unknown>)[GIT_ENV_SETUP_MARKER] = true;
