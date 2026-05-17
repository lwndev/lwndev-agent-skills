#!/usr/bin/env tsx
/**
 * NFR-5 enforcing check (FEAT-033).
 *
 * Walks shell scripts under `plugins/lwndev-sdlc/skills/**` and
 * `plugins/lwndev-sdlc/scripts/**` and flags any inline `gh pr`, `gh issue`,
 * `az repos`, or `az boards` invocation outside the two source-of-truth dirs:
 *
 *   - plugins/lwndev-sdlc/skills/managing-source-control/scripts/**
 *   - plugins/lwndev-sdlc/skills/managing-work-items/scripts/**
 *
 * "Inline invocation" means the pattern appears at command position. The
 * validator strips shell comments and single/double-quoted strings before
 * matching so that:
 *   - Comment lines (`# gh pr merge*`)
 *   - Warning / error strings (`echo "[warn] gh pr ..."`)
 *   - Case patterns (`"gh pr merge "*|...`)
 *   - Grep patterns matching CLI output
 * are NOT flagged. Genuine command invocations (`gh pr create`,
 * `az repos pr update`, etc.) at the start of a statement ARE flagged.
 *
 * Out of scope: SKILL.md / reference markdown / fixture assets. The NFR-5
 * contract targets executable shell code, not prose. Documentation may
 * legitimately describe dispatcher internals using `gh pr ...` / `az repos
 * ...` phrasing as part of explaining what `create-pr.sh` / `merge-pr.sh`
 * etc. do. Reviewers should still call out any markdown that *instructs*
 * a caller to invoke `gh`/`az` directly instead of going through the
 * managing-source-control dispatcher — but that is a manual review concern,
 * not a regex one (we would generate false positives for every reference
 * doc that names the underlying CLI).
 *
 * Output format:
 *   [validate-no-inline-scm] FAIL: <path>:<line>: <matched-line>
 *   <N> violations
 *
 * Exit code:
 *   0 — no violations.
 *   1 — one or more violations.
 */

import { readdir, readFile, stat } from 'node:fs/promises';
import { join, sep } from 'node:path';

/** Roots scanned for inline SCM calls. */
const SCAN_ROOTS = ['plugins/lwndev-sdlc/skills', 'plugins/lwndev-sdlc/scripts'];

/**
 * POSIX-form path prefixes whose contents are allowed to contain inline `gh`
 * and `az` calls. These are the two skills that own SCM and work-item
 * operations respectively.
 */
const ALLOW_LIST_PREFIXES = [
  'plugins/lwndev-sdlc/skills/managing-source-control/scripts/',
  'plugins/lwndev-sdlc/skills/managing-work-items/scripts/',
];

/** Directory names skipped during the walk. */
const SKIP_DIRS = new Set(['node_modules', '.git', 'dist', 'dist-scripts', 'coverage']);

/**
 * Inline-call patterns. Each pattern is matched against a "stripped" version
 * of the line that has comments and quoted strings removed, so warnings and
 * documentation in scripts do not false-positive.
 */
const INLINE_PATTERNS = [/\bgh\s+pr\b/, /\bgh\s+issue\b/, /\baz\s+repos\b/, /\baz\s+boards\b/];

interface Violation {
  path: string;
  line: number;
  text: string;
}

async function walk(root: string, out: string[]): Promise<void> {
  let entries;
  try {
    entries = await readdir(root, { withFileTypes: true });
  } catch (err: unknown) {
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
      if (entry.isSymbolicLink()) {
        try {
          const s = await stat(full);
          if (!s.isFile()) continue;
        } catch {
          continue;
        }
      }
      if (entry.name.endsWith('.sh')) out.push(full);
    }
  }
}

function toPosix(p: string): string {
  if (sep === '/') return p;
  return p.split(sep).join('/');
}

function isAllowed(posixPath: string): boolean {
  return ALLOW_LIST_PREFIXES.some((prefix) => posixPath.startsWith(prefix));
}

/**
 * Strip shell comments and quoted strings from a line. We replace quoted
 * regions with empty strings (preserving the rest of the line) so a command
 * like `echo "[warn] gh pr ..." >&2` becomes `echo  >&2` and contributes no
 * match. We also handle `#` comments outside of quoted strings.
 *
 * Heuristic, not a full shell parser — but sufficient for the inline-call
 * detection problem and aligned with how the project's other lightweight
 * validators operate.
 */
function stripQuotesAndComments(line: string): string {
  let out = '';
  let i = 0;
  while (i < line.length) {
    const ch = line[i];

    // Comment marker: end of line.
    if (ch === '#') {
      // Treat as comment only if it's at the start of the line or preceded
      // by whitespace (avoids tripping on `$#` parameter or `${var#prefix}`).
      const prev = i > 0 ? line[i - 1] : ' ';
      if (prev === ' ' || prev === '\t' || i === 0) {
        break;
      }
    }

    // Double-quoted string: skip to matching `"` (honor backslash escapes).
    if (ch === '"') {
      i++;
      while (i < line.length && line[i] !== '"') {
        if (line[i] === '\\' && i + 1 < line.length) i += 2;
        else i++;
      }
      i++; // skip closing quote (or end of line)
      continue;
    }

    // Single-quoted string: literal — skip to next `'`.
    if (ch === "'") {
      i++;
      while (i < line.length && line[i] !== "'") i++;
      i++;
      continue;
    }

    out += ch;
    i++;
  }
  return out;
}

async function main(): Promise<void> {
  const violations: Violation[] = [];

  for (const root of SCAN_ROOTS) {
    const files: string[] = [];
    await walk(root, files);
    for (const f of files) {
      const rel = toPosix(f);
      if (isAllowed(rel)) continue;

      const content = await readFile(f, 'utf-8');
      const lines = content.split('\n');
      for (let i = 0; i < lines.length; i++) {
        const stripped = stripQuotesAndComments(lines[i]);
        if (INLINE_PATTERNS.some((p) => p.test(stripped))) {
          violations.push({ path: rel, line: i + 1, text: lines[i].trim() });
        }
      }
    }
  }

  violations.sort((a, b) => a.path.localeCompare(b.path) || a.line - b.line);

  for (const v of violations) {
    console.log(`[validate-no-inline-scm] FAIL: ${v.path}:${v.line}: ${v.text}`);
  }

  if (violations.length === 0) {
    console.log('[info] No inline SCM calls found outside source-of-truth directories.');
    process.exit(0);
  }

  console.log(`${violations.length} violations`);
  process.exit(1);
}

main().catch((err) => {
  console.error('[validate-no-inline-scm] error:', err);
  process.exit(2);
});
