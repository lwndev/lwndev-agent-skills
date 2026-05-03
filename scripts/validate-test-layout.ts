#!/usr/bin/env tsx
/**
 * Layout validator (FR-9).
 *
 * Walks the working tree under known roots (scripts/, plugins/, tests/, and
 * the repo-root-level files) and emits one line per layout violation. Imports
 * the rule definitions from `scripts/test-layout-rules.ts` so this validator
 * and the PreToolUse hook (FR-10) cannot diverge on rule IDs or the allow-rule
 * (Edge Case 5).
 *
 * Output format (per the FEAT-031 requirements doc Output Format section):
 *
 *   [validate-test-layout] FAIL: <path> -> rule=<rule>
 *   <N> violations
 *
 * Exit code:
 *   0 — clean tree, no violations.
 *   1 — one or more violations.
 */

import { readdir, stat } from 'node:fs/promises';
import { join, sep } from 'node:path';
import { classifyPath } from './test-layout-rules.js';

/**
 * Roots to walk. Repo-root-relative. The classifier itself is the gate: a path
 * outside these roots simply isn't visited, but anything within them is
 * classified, so adding a root here can only ever surface violations — not
 * suppress them.
 */
const WALK_ROOTS = ['scripts', 'plugins', 'tests'];

/**
 * Directory names skipped during the walk. These are either out-of-tree
 * artifacts or known noise that cannot contain test files.
 */
const SKIP_DIRS = new Set(['node_modules', '.git', 'dist', 'dist-scripts', 'coverage']);

interface Violation {
  path: string;
  rule: string;
}

async function walk(root: string, out: string[]): Promise<void> {
  let entries;
  try {
    entries = await readdir(root, { withFileTypes: true });
  } catch (err: unknown) {
    // Missing root is fine — e.g., tests/ may not exist on a fresh worktree.
    const code = (err as NodeJS.ErrnoException).code;
    if (code === 'ENOENT') return;
    throw err;
  }
  for (const entry of entries) {
    if (SKIP_DIRS.has(entry.name)) continue;
    const full = join(root, entry.name);
    if (entry.isDirectory()) {
      await walk(full, out);
    } else if (entry.isFile() || entry.isSymbolicLink()) {
      // Resolve symlinks to a stat to ensure we don't classify dangling links
      // as files. A dangling link simply gets skipped.
      if (entry.isSymbolicLink()) {
        try {
          const s = await stat(full);
          if (!s.isFile()) continue;
        } catch {
          continue;
        }
      }
      out.push(full);
    }
  }
}

/**
 * Repo-root-relative POSIX form. The walker emits platform-native paths; the
 * classifier expects POSIX-form repo-root-relative input, and the output
 * contract reads cleanest with forward slashes.
 */
function toPosix(p: string): string {
  if (sep === '/') return p;
  return p.split(sep).join('/');
}

async function main(): Promise<void> {
  const violations: Violation[] = [];

  for (const root of WALK_ROOTS) {
    const files: string[] = [];
    await walk(root, files);
    for (const f of files) {
      const rel = toPosix(f);
      const result = classifyPath(rel);
      if (result) {
        violations.push({ path: rel, rule: result.rule });
      }
    }
  }

  // Stable ordering for deterministic output.
  violations.sort((a, b) => a.path.localeCompare(b.path));

  for (const v of violations) {
    console.log(`[validate-test-layout] FAIL: ${v.path} -> rule=${v.rule}`);
  }
  console.log(`${violations.length} violations`);

  process.exit(violations.length > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error('[validate-test-layout] error:', err);
  process.exit(2);
});
