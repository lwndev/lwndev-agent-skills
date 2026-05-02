#!/usr/bin/env tsx
/**
 * PreToolUse enforcement hook (FR-10).
 *
 * Reads the Claude Code hook payload from stdin, extracts
 * `tool_input.file_path`, and rejects Write/Edit calls that would place a
 * test file at a path that violates the FEAT-031 layout rules.
 *
 * Fail-open by design (Edge Case 4): any parse error, missing field, or
 * unexpected input results in exit 0 so a malformed payload never blocks
 * legitimate work.
 *
 * Imports `classifyPath` and `CANONICAL_DESTINATIONS` from
 * `scripts/test-layout-rules.ts` — the same module used by
 * `scripts/validate-test-layout.ts` — so the rule IDs and allow-rule cannot
 * diverge between the two tools (Edge Case 5).
 *
 * Rejection output format (stdout):
 *   [validate-test-layout-hook] reject: <path> violates <rule>; canonical destination: <dest>
 *
 * Exit codes:
 *   0 — path is allowed, or fail-open (parse error / non-test path).
 *   1 — path violates a layout rule (hook rejects the Write/Edit).
 */

import { classifyPath, CANONICAL_DESTINATIONS } from '../test-layout-rules.js';

async function main(): Promise<void> {
  // Read all of stdin.
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  const raw = Buffer.concat(chunks).toString('utf8').trim();

  // Fail open on empty input.
  if (!raw) {
    process.exit(0);
  }

  // Parse JSON — fail open on error (Edge Case 4).
  let payload: unknown;
  try {
    payload = JSON.parse(raw);
  } catch {
    process.exit(0);
  }

  // Extract tool_input.file_path — fail open if missing or wrong type.
  if (
    typeof payload !== 'object' ||
    payload === null ||
    !('tool_input' in payload) ||
    typeof (payload as Record<string, unknown>).tool_input !== 'object' ||
    (payload as Record<string, unknown>).tool_input === null
  ) {
    process.exit(0);
  }

  const toolInput = (payload as Record<string, unknown>).tool_input as Record<string, unknown>;
  const filePath = toolInput.file_path;

  if (typeof filePath !== 'string' || !filePath) {
    process.exit(0);
  }

  // Classify the path against the layout rules.
  const result = classifyPath(filePath);

  if (!result) {
    // Allowed — no rule fired.
    process.exit(0);
  }

  // Violation: emit rejection message and exit non-zero.
  const dest = CANONICAL_DESTINATIONS[result.rule] ?? 'tests/unit/ or tests/bats/';
  process.stdout.write(
    `[validate-test-layout-hook] reject: ${filePath} violates ${result.rule}; canonical destination: ${dest}\n`
  );
  process.exit(1);
}

main().catch(() => {
  // Fail open on unexpected errors.
  process.exit(0);
});
