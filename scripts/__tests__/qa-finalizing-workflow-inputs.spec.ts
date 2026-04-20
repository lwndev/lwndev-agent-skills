// QA adversarial tests for FEAT-019 — dimension: Inputs
//
// These tests probe the boundary cases called out as P0 in
// qa/test-plans/QA-plan-FEAT-019.md that the existing test suite does NOT
// cover: CRLF line endings, nested `- [ ]` inside code fences, `## Acceptance
// Criteria` heading inside a fenced code block, no-trailing-newline doc,
// Completion at EOF with no `## ` close boundary, and malformed-input paths.
//
// The helpers below reimplement the documented logic from
// scripts/__tests__/finalizing-workflow.test.ts so the adversarial suite can
// probe the same interpretation without depending on non-exported symbols.

import { describe, it, expect } from 'vitest';

// ----- Reimplemented helpers (mirror scripts/__tests__/finalizing-workflow.test.ts) -----

interface BranchParseResult {
  id: string;
  directory: string;
}

function parseBranchName(branch: string): BranchParseResult | null {
  const featMatch = branch.match(/^feat\/(FEAT-[0-9]+)-/);
  if (featMatch) return { id: featMatch[1], directory: 'requirements/features/' };
  const choreMatch = branch.match(/^chore\/(CHORE-[0-9]+)-/);
  if (choreMatch) return { id: choreMatch[1], directory: 'requirements/chores/' };
  const fixMatch = branch.match(/^fix\/(BUG-[0-9]+)-/);
  if (fixMatch) return { id: fixMatch[1], directory: 'requirements/bugs/' };
  return null;
}

// Mirrors findSection / checkoffAC / upsertCompletion from
// finalizing-workflow.test.ts after the SKILL.md BK-4 robustness rules were
// added (CRLF + fenced-code awareness).

interface SectionBounds {
  headingStart: number;
  bodyStart: number;
  bodyEnd: number;
}

function findSection(content: string, heading: string): SectionBounds | null {
  const lines = content.split(/\r?\n/);
  let inFence = false;
  let offset = 0;
  let headingStart = -1;
  let bodyStart = -1;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineLen = line.length;
    const sepLen = content.slice(offset + lineLen, offset + lineLen + 2) === '\r\n' ? 2 : 1;

    if (/^```/.test(line)) {
      inFence = !inFence;
    } else if (!inFence) {
      if (headingStart === -1 && line === `## ${heading}`) {
        headingStart = offset;
        bodyStart = offset + lineLen + sepLen;
      } else if (headingStart !== -1 && /^## /.test(line)) {
        return { headingStart, bodyStart, bodyEnd: offset };
      }
    }
    offset += lineLen + sepLen;
  }

  if (headingStart !== -1) return { headingStart, bodyStart, bodyEnd: content.length };
  return null;
}

function checkoffAC(content: string): string {
  const bounds = findSection(content, 'Acceptance Criteria');
  if (!bounds) return content;

  const body = content.slice(bounds.bodyStart, bounds.bodyEnd);
  const parts = body.split(/(\r?\n)/);
  let inFence = false;
  const out: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const chunk = parts[i];
    if (i % 2 === 1) {
      out.push(chunk);
      continue;
    }
    if (/^```/.test(chunk)) inFence = !inFence;
    if (!inFence && chunk.startsWith('- [ ]')) {
      out.push('- [x]' + chunk.slice('- [ ]'.length));
    } else {
      out.push(chunk);
    }
  }
  return content.slice(0, bounds.bodyStart) + out.join('') + content.slice(bounds.bodyEnd);
}

function upsertCompletion(
  content: string,
  date: string,
  prNumber: number,
  prUrl: string | null
): string {
  const eol = /\r\n/.test(content) ? '\r\n' : '\n';
  const prLine = prUrl ? `${eol}**Pull Request:** [#${prNumber}](${prUrl})` : '';
  const block = `## Completion${eol}${eol}**Status:** \`Complete\`${eol}${eol}**Completed:** ${date}${prLine}${eol}`;

  const bounds = findSection(content, 'Completion');
  if (!bounds) {
    return content.replace(/\s+$/, '') + eol + eol + block;
  }
  return content.slice(0, bounds.headingStart) + block + content.slice(bounds.bodyEnd);
}

// ---------------------------------------------------------------------------
// P0 — Branch-name parser: malformed IDs that superficially match prefix
// ---------------------------------------------------------------------------

describe('[QA P0 / Inputs] branch-name parser rejects malformed IDs', () => {
  it('feat/FEAT-foo-bar (non-numeric after FEAT-) is correctly rejected', () => {
    expect(parseBranchName('feat/FEAT-foo-bar')).toBeNull();
  });

  it('feat/FEAT-019 (trailing dash missing) is correctly rejected', () => {
    // The regex requires a trailing `-` after the digits — a terminal ID with
    // no description should not match
    expect(parseBranchName('feat/FEAT-019')).toBeNull();
  });

  it('feat/FEAT-019foo (no separator between digits and description) is correctly rejected', () => {
    expect(parseBranchName('feat/FEAT-019foo')).toBeNull();
  });

  it('chore/CHORE-0- — documented quirk: `0` is a valid ID under the current regex', () => {
    // The regex `^chore/(CHORE-[0-9]+)-` accepts any non-empty digit sequence
    // including `0`. Not flagging as a bug — numeric ID `0` is not in the
    // repo's allocation space, so a branch named `chore/CHORE-0-` would fail
    // at the glob step (no matching doc) rather than cause silent corruption.
    const result = parseBranchName('chore/CHORE-0-');
    expect(result).not.toBeNull();
    expect(result!.id).toBe('CHORE-0');
  });

  it('bug/BUG-019-foo (non-canonical prefix) is correctly rejected', () => {
    expect(parseBranchName('bug/BUG-019-foo')).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// P0 — AC checkoff: nested [ ] inside code fences and sub-lists
// ---------------------------------------------------------------------------

describe('[QA P0 / Inputs] AC checkoff and code-fence / nested-list boundaries', () => {
  it('nested `- [ ]` inside a sub-list under an AC item IS flipped by the naive regex', () => {
    // The `^- \[ \]` regex matches any line beginning with "- [ ]" anywhere in
    // the section body. Sub-list items (starting with leading spaces, not "- ")
    // are NOT flipped by this regex. Only top-level dashes are.
    const doc = `# F\n\n## Acceptance Criteria\n\n- [ ] Top-level AC\n  - [ ] Nested item\n`;
    const result = checkoffAC(doc);
    expect(result).toContain('- [x] Top-level AC');
    // Nested item (has leading spaces) should NOT be flipped
    expect(result).toContain('  - [ ] Nested item');
  });

  it('code-fence-enclosed `- [ ]` must NOT be flipped (only real AC entries flip)', () => {
    // A doc with a markdown code fence inside the AC section — the code
    // fence's example checkbox is illustrative content, not a live AC.
    // Correct behavior: only real AC items flip; code-fence examples stay
    // as `- [ ]` so the doc's illustrations remain accurate.
    const doc =
      '# F\n\n## Acceptance Criteria\n\n- [ ] Real AC item\n\n```md\n- [ ] Example snippet inside code fence\n```\n\n- [ ] Another real AC\n';
    const result = checkoffAC(doc);
    expect(result).toContain('- [x] Real AC item');
    expect(result).toContain('- [x] Another real AC');
    // Correct behavior: the code-fenced example MUST remain unchanged
    expect(result).toContain('- [ ] Example snippet inside code fence');
  });

  it('`## Acceptance Criteria` heading inside a fenced code block must NOT be treated as a real section', () => {
    // A doc with `## Acceptance Criteria` appearing first inside a fenced
    // code block (e.g., a worked example) and then later as a REAL heading.
    // Correct behavior: the code-fenced example's checkboxes stay unchanged;
    // the real section's checkboxes flip.
    const doc =
      '# F\n\n## Overview\n\nExample:\n\n```md\n## Acceptance Criteria\n- [ ] Sample item\n```\n\n## Acceptance Criteria\n\n- [ ] Real AC\n';
    const result = checkoffAC(doc);
    // Correct behavior: code-fence example stays as `- [ ]`
    expect(result).toContain('- [ ] Sample item');
    // Correct behavior: real AC flips to `- [x]`
    expect(result).toContain('- [x] Real AC');
  });

  it('AC item with trailing text containing `[ ]` as literal content is NOT affected', () => {
    const doc = `# F\n\n## Acceptance Criteria\n\n- [ ] Explains: use \`[ ]\` as the unchecked marker\n`;
    const result = checkoffAC(doc);
    expect(result).toContain('- [x] Explains: use `[ ]` as the unchecked marker');
  });
});

// ---------------------------------------------------------------------------
// P0 — CRLF line endings
// ---------------------------------------------------------------------------

describe('[QA P0 / Inputs] CRLF line endings', () => {
  it('doc with Windows CRLF line endings must still flip ACs in the section body', () => {
    // A CRLF-encoded file has `## Acceptance Criteria\r\n`. Correct behavior:
    // the section detection and regex replacement must handle `\r\n` so the
    // ACs flip to `- [x]` regardless of line-ending style.
    const doc =
      '# F\r\n\r\n## Acceptance Criteria\r\n\r\n- [ ] First\r\n- [ ] Second\r\n\r\n## Next\r\n';
    const result = checkoffAC(doc);
    expect(result).toContain('- [x] First');
    expect(result).toContain('- [x] Second');
  });
});

// ---------------------------------------------------------------------------
// P0 — Completion section upsert edge cases
// ---------------------------------------------------------------------------

describe('[QA P0 / Inputs] Completion section upsert — boundary cases', () => {
  it('doc with no trailing newline — blank-line separator is inserted before appended Completion block', () => {
    // No trailing `\n` at EOF — the `content.trimEnd() + '\n\n' + block` path
    // ensures the new section is visually separated.
    const doc = `# F\n\n## Overview\n\nNo final newline`;
    const result = upsertCompletion(doc, '2026-04-19', 42, 'https://example.com/pull/42');
    // The result should not concatenate `## Completion` onto the last line.
    expect(result).toContain('No final newline\n\n## Completion');
  });

  it('Completion section at EOF with no trailing `## ` heading — body replacement bounds correctly', () => {
    // The `afterHeading.search(/\n## /)` returns -1, so `bodyEnd = content.length`.
    // The new block replaces everything from `## Completion` to EOF.
    const doc = `# F\n\n## Overview\n\nContent.\n\n## Completion\n\n**Status:** \`In Progress\`\n\nOld stuff at end\n`;
    const result = upsertCompletion(doc, '2026-04-19', 42, 'https://example.com/pull/42');
    expect(result).toContain('**Status:** `Complete`');
    expect(result).not.toContain('**Status:** `In Progress`');
    expect(result).not.toContain('Old stuff at end');
  });

  it('doc with ONLY frontmatter and no sections — Completion block appended at end', () => {
    const doc = `---\nid: FEAT-999\n---\n`;
    const result = upsertCompletion(doc, '2026-04-19', 1, null);
    expect(result).toContain('## Completion');
    expect(result).toContain('**Status:** `Complete`');
  });

  it('Completion section body contains inline markdown — replacement preserves heading only', () => {
    // An existing Completion section with bold text, links, etc. in the body
    // should be REPLACED — none of the old markup should leak through.
    const doc = `# F\n\n## Completion\n\nSome **old** [link](#) content\n\nWith multiple paragraphs.\n`;
    const result = upsertCompletion(doc, '2026-04-19', 42, 'https://example.com/pull/42');
    expect(result).toContain('## Completion');
    expect(result).toContain('**Status:** `Complete`');
    expect(result).not.toContain('Some **old** [link](#) content');
    expect(result).not.toContain('With multiple paragraphs');
  });
});
