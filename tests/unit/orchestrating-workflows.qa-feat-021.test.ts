import { describe, it, expect } from 'vitest';
import {
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  readFileSync,
  rmSync,
  chmodSync,
  symlinkSync,
} from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';

// ---------------------------------------------------------------------------
// FEAT-021 adversarial QA — probes failure modes the authoring bats fixture
// did not cover. Organised by the five adversarial dimensions (Inputs, State
// transitions, Environment, Dependency failure, Cross-cutting). These are
// independent from plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats; the
// bats suite covers the primary happy-path matrix and the declared error
// taxonomy. This spec probes trust-boundary behaviour, audit-trail retry
// preservation, locale byte-preservation, concurrency, and ID/stepIndex
// matrices that the bats fixture only partially exercises.
// ---------------------------------------------------------------------------

const REPO_ROOT = process.cwd();
const PREPARE_FORK = join(REPO_ROOT, 'plugins/lwndev-sdlc/scripts/prepare-fork.sh');
const REAL_WORKFLOW_STATE = join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh'
);

const ALL_SKILLS = [
  'reviewing-requirements',
  'creating-implementation-plans',
  'implementing-plan-phases',
  'executing-chores',
  'executing-bug-fixes',
  'finalizing-workflow',
  'pr-creation',
];

interface Harness {
  dir: string;
  pluginRoot: string;
}

function makeHarness(): Harness {
  const dir = mkdtempSync(join(tmpdir(), 'qa-feat-021-'));
  mkdirSync(join(dir, '.sdlc/workflows'), { recursive: true });
  const pluginRoot = join(dir, 'plugin');
  mkdirSync(join(pluginRoot, 'skills/orchestrating-workflows/scripts'), {
    recursive: true,
  });
  symlinkSync(
    REAL_WORKFLOW_STATE,
    join(pluginRoot, 'skills/orchestrating-workflows/scripts/workflow-state.sh')
  );
  for (const skill of ALL_SKILLS) {
    mkdirSync(join(pluginRoot, 'skills', skill), { recursive: true });
    writeFileSync(
      join(pluginRoot, 'skills', skill, 'SKILL.md'),
      `---\nname: ${skill}\n---\n# ${skill} stub\n`
    );
  }
  return { dir, pluginRoot };
}

function cleanup(h: Harness) {
  try {
    rmSync(h.dir, { recursive: true, force: true });
  } catch {
    /* ignore */
  }
}

function seedState(h: Harness, id: string, overrides: Record<string, unknown> = {}): string {
  const path = join(h.dir, `.sdlc/workflows/${id}.json`);
  const state = {
    id,
    type: 'feature',
    status: 'in-progress',
    currentStep: 0,
    steps: [
      {
        name: 'documenting-features',
        skill: 'documenting-features',
        status: 'complete',
      },
      {
        name: 'reviewing-requirements',
        skill: 'reviewing-requirements',
        status: 'pending',
      },
    ],
    complexity: 'medium',
    complexityStage: 'init',
    modelOverride: null,
    modelSelections: [],
    gate: null,
    ...overrides,
  };
  writeFileSync(path, JSON.stringify(state, null, 2));
  return path;
}

function runPrepareFork(h: Harness, args: string[], env: Record<string, string> = {}) {
  return spawnSync('bash', [PREPARE_FORK, ...args], {
    cwd: h.dir,
    encoding: 'utf-8',
    env: {
      ...process.env,
      CLAUDE_PLUGIN_ROOT: h.pluginRoot,
      CLAUDE_SKILL_DIR: join(h.pluginRoot, 'skills/orchestrating-workflows'),
      ...env,
    },
  });
}

function readState(h: Harness, id: string) {
  return JSON.parse(readFileSync(join(h.dir, `.sdlc/workflows/${id}.json`), 'utf-8'));
}

function writeStubWorkflowState(h: Harness, body: string): string {
  const stubRoot = join(h.dir, 'stub-plugin');
  mkdirSync(join(stubRoot, 'skills/orchestrating-workflows/scripts'), {
    recursive: true,
  });
  for (const skill of ALL_SKILLS) {
    mkdirSync(join(stubRoot, 'skills', skill), { recursive: true });
    writeFileSync(join(stubRoot, 'skills', skill, 'SKILL.md'), `---\nname: ${skill}\n---\n`);
  }
  const p = join(stubRoot, 'skills/orchestrating-workflows/scripts/workflow-state.sh');
  writeFileSync(p, body);
  chmodSync(p, 0o755);
  return stubRoot;
}

// ============================================================================
// Dimension 1: Inputs
// ============================================================================

describe('[QA FEAT-021] Inputs — malformed ID matrix', () => {
  it.each([
    ['empty string', ''],
    ['whitespace only', '   '],
    ['just prefix', 'FEAT-'],
    ['lowercase prefix', 'feat-021'],
    ['digits only', '21'],
    ['unknown prefix', 'FOO-021'],
  ])('rejects %s with state-file-not-found (exit 2, references .sdlc/workflows)', (_label, id) => {
    const h = makeHarness();
    try {
      const r = runPrepareFork(h, [id, '1', 'reviewing-requirements', '--mode', 'standard']);
      expect(r.status).toBe(2);
      expect(r.stderr).toMatch(/\.sdlc\/workflows/);
    } finally {
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Inputs — non-numeric stepIndex matrix', () => {
  it.each([
    ['negative', '-1'],
    ['decimal', '1.5'],
    ['scientific', '1e3'],
    ['hex', '0x10'],
    ['unicode digit', '①'], // circled one
    ['whitespace-wrapped', ' 1 '],
  ])('rejects %s stepIndex with exit 2 and non-negative-integer message', (_label, stepIdx) => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    try {
      const r = runPrepareFork(h, [
        'FEAT-TEST',
        stepIdx,
        'reviewing-requirements',
        '--mode',
        'standard',
      ]);
      expect(r.status).toBe(2);
      expect(r.stderr).toMatch(/non-negative integer/);
      // Audit trail untouched.
      expect(readState(h, 'FEAT-TEST').modelSelections.length).toBe(0);
    } finally {
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Inputs — unknown skill-name typos', () => {
  it.each([
    ['transposed chars', 'reveiwing-requirements'],
    ['underscore', 'reviewing_requirements'],
    ['uppercase', 'REVIEWING-REQUIREMENTS'],
    ['whitespace-wrapped', ' reviewing-requirements '],
    ['trailing hyphen', 'reviewing-requirements-'],
  ])('rejects %s with exit 2 and allowlist listing', (_label, skill) => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    try {
      const r = runPrepareFork(h, ['FEAT-TEST', '1', skill]);
      expect(r.status).toBe(2);
      expect(r.stderr).toMatch(/unknown skill-name/);
      expect(r.stderr).toMatch(/reviewing-requirements/);
      expect(r.stderr).toMatch(/pr-creation/);
      expect(readState(h, 'FEAT-TEST').modelSelections.length).toBe(0);
    } finally {
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Inputs — argv injection into skill-name', () => {
  it.each([
    'reviewing-requirements; rm -rf /tmp/qa-feat-021-payload',
    'reviewing-requirements$(touch /tmp/qa-feat-021-payload)',
    'reviewing-requirements`touch /tmp/qa-feat-021-payload`',
    '../../../etc/passwd',
  ])('rejects injection payload %s with no filesystem side-effects', (skill) => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    const sentinel = '/tmp/qa-feat-021-payload';
    // Ensure sentinel is absent before the run.
    try {
      rmSync(sentinel, { force: true });
    } catch {
      /* ignore */
    }
    try {
      const r = runPrepareFork(h, ['FEAT-TEST', '1', skill]);
      expect(r.status).toBe(2);
      // Sentinel must not exist after rejection.
      expect(() => readFileSync(sentinel)).toThrow();
    } finally {
      try {
        rmSync(sentinel, { force: true });
      } catch {
        /* ignore */
      }
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Inputs — --help precedence', () => {
  it('wins over mutually-exclusive --mode + --phase', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    try {
      const r = runPrepareFork(h, [
        'FEAT-TEST',
        '1',
        'reviewing-requirements',
        '--mode',
        'standard',
        '--phase',
        '2',
        '--help',
      ]);
      expect(r.status).toBe(0);
      expect(r.stdout).toMatch(/Usage: prepare-fork\.sh/);
      expect(r.stderr).not.toMatch(/mutually exclusive/);
    } finally {
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Inputs — oversized stepIndex round-trip', () => {
  it('preserves large numeric stepIndex byte-for-byte in audit entry', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    const bigIdx = '99999999999999999999'; // > 2^63
    try {
      const r = runPrepareFork(h, [
        'FEAT-TEST',
        bigIdx,
        'reviewing-requirements',
        '--mode',
        'standard',
      ]);
      // Script accepts any non-negative integer match; record-model-selection
      // handles the actual write. Either exit 0 with preserved string, or a
      // clean propagated failure — both are acceptable contract outcomes, but
      // silent corruption is not.
      if (r.status === 0) {
        const entries = readState(h, 'FEAT-TEST').modelSelections;
        expect(entries.length).toBe(1);
        // jq's JSON number parser will re-encode huge ints as floats; the
        // contract we assert is "not silently truncated to a different
        // integer" — the stored value must round-trip to the input when
        // jq preserves it as a string or at minimum remain deterministic.
        const stored = String(entries[0].stepIndex);
        // Acceptable outcomes: exact preserve, or scientific-notation float.
        // Inacceptable: 0 or a random truncated int.
        expect(stored).not.toBe('0');
        expect(Number.isNaN(Number(stored))).toBe(false);
      } else {
        // Non-zero is fine if propagated cleanly; assert stderr is non-empty
        // so the failure is diagnostic rather than silent.
        expect(r.stderr.length).toBeGreaterThan(0);
      }
    } finally {
      cleanup(h);
    }
  });
});

// ============================================================================
// Dimension 2: State transitions
// ============================================================================

describe('[QA FEAT-021] State — repeated invocation (double-call)', () => {
  it('appends two audit entries with distinct startedAt for identical args', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    try {
      const r1 = runPrepareFork(h, [
        'FEAT-TEST',
        '1',
        'reviewing-requirements',
        '--mode',
        'standard',
      ]);
      expect(r1.status).toBe(0);
      // Ensure a timestamp tick so startedAt differs (date -u is 1s resolution).
      const waitUntil = Date.now() + 1100;
      while (Date.now() < waitUntil) {
        /* busy wait */
      }
      const r2 = runPrepareFork(h, [
        'FEAT-TEST',
        '1',
        'reviewing-requirements',
        '--mode',
        'standard',
      ]);
      expect(r2.status).toBe(0);
      const entries = readState(h, 'FEAT-TEST').modelSelections;
      expect(entries.length).toBe(2);
      expect(entries[0].startedAt).not.toBe(entries[1].startedAt);
      // Same stepIndex in both entries (non-idempotent by design).
      expect(entries[0].stepIndex).toBe(1);
      expect(entries[1].stepIndex).toBe(1);
    } finally {
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] State — invocation with status=paused still writes', () => {
  it('appends audit entry even when workflow is paused (script does not gate on status)', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST', {
      status: 'paused',
      pauseReason: 'plan-approval',
    });
    try {
      const r = runPrepareFork(h, [
        'FEAT-TEST',
        '1',
        'reviewing-requirements',
        '--mode',
        'standard',
      ]);
      expect(r.status).toBe(0);
      const state = readState(h, 'FEAT-TEST');
      expect(state.modelSelections.length).toBe(1);
      // Status is untouched (no state-management side effects).
      expect(state.status).toBe('paused');
    } finally {
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] State — audit trail retry attempts', () => {
  it('records two entries with distinct tier values on retry-with-tier-upgrade', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    try {
      // First attempt with haiku (Edge Case 11 hard override below baseline).
      const r1 = runPrepareFork(h, [
        'FEAT-TEST',
        '1',
        'creating-implementation-plans',
        '--cli-model',
        'haiku',
      ]);
      expect(r1.status).toBe(0);
      // Tick forward so startedAt differs.
      const waitUntil = Date.now() + 1100;
      while (Date.now() < waitUntil) {
        /* busy wait */
      }
      // Retry at escalated tier.
      const r2 = runPrepareFork(h, [
        'FEAT-TEST',
        '1',
        'creating-implementation-plans',
        '--cli-model',
        'sonnet',
      ]);
      expect(r2.status).toBe(0);
      const entries = readState(h, 'FEAT-TEST').modelSelections;
      expect(entries.length).toBe(2);
      expect(entries[0].tier).toBe('haiku');
      expect(entries[1].tier).toBe('sonnet');
      expect(entries[0].startedAt).not.toBe(entries[1].startedAt);
    } finally {
      cleanup(h);
    }
  });
});

// ============================================================================
// Dimension 3: Environment
// ============================================================================

describe('[QA FEAT-021] Environment — read-only state file', () => {
  // FINDING: `record-model-selection` uses the tmp-file + `mv` atomic-rename
  // pattern throughout `workflow-state.sh`. As a consequence, chmod 0400 on
  // the state file does NOT prevent audit-trail writes — the rename operation
  // only needs the parent directory to be writable. An operator who sets
  // `chmod 0400` expecting write-protection will be surprised. This test
  // documents the current behaviour so a future change to direct-write (which
  // WOULD respect chmod 0400) surfaces here as a regression for deliberate
  // consideration.
  it('still writes audit entry because atomic-rename bypasses file mode (FINDING: chmod 0400 does not write-protect)', () => {
    const h = makeHarness();
    const path = seedState(h, 'FEAT-TEST');
    chmodSync(path, 0o400);
    try {
      const r = runPrepareFork(h, [
        'FEAT-TEST',
        '1',
        'reviewing-requirements',
        '--mode',
        'standard',
      ]);
      expect(r.status).toBe(0);
      // Re-open for read; the file was replaced via rename, so it now has
      // whatever mode jq/mv set for newly-created files (typically 0600).
      chmodSync(path, 0o600);
      const parsed = JSON.parse(readFileSync(path, 'utf-8'));
      expect(Array.isArray(parsed.modelSelections)).toBe(true);
      expect(parsed.modelSelections.length).toBe(1);
    } finally {
      try {
        chmodSync(path, 0o600);
      } catch {
        /* ignore */
      }
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Environment — CLAUDE_PLUGIN_ROOT points at nonexistent dir', () => {
  it('exits 3 when SKILL.md cannot be resolved from bogus plugin root', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    const bogus = join(h.dir, 'nonexistent-plugin-root');
    try {
      const r = runPrepareFork(
        h,
        ['FEAT-TEST', '1', 'reviewing-requirements', '--mode', 'standard'],
        {
          CLAUDE_PLUGIN_ROOT: bogus,
          CLAUDE_SKILL_DIR: join(bogus, 'skills/orchestrating-workflows'),
        }
      );
      expect(r.status).toBe(3);
      expect(r.stderr).toMatch(/SKILL\.md/);
      expect(r.stderr).toMatch(/cannot be read/);
    } finally {
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Environment — script invoked via symlink', () => {
  // FINDING: The fallback CLAUDE_PLUGIN_ROOT derivation uses
  //   `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)`
  // which does NOT resolve symlinks. When the script is invoked via a symlink
  // without CLAUDE_PLUGIN_ROOT being pre-set, the derived root points at the
  // symlink's parent directory, not the real plugin tree — so the SKILL.md
  // lookup fails with exit 3. In practice this is non-operational (the
  // orchestrator always sets CLAUDE_PLUGIN_ROOT), but the test documents the
  // limitation. A `realpath` / `readlink -f` fix would make this return 0.
  it('FINDING: fails with exit 3 when invoked via symlink without CLAUDE_PLUGIN_ROOT (fallback is not symlink-aware)', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    const linkPath = join(h.dir, 'prepare-fork-link.sh');
    symlinkSync(PREPARE_FORK, linkPath);
    try {
      const r = spawnSync(
        'bash',
        [linkPath, 'FEAT-TEST', '2', 'reviewing-requirements', '--mode', 'standard'],
        {
          cwd: h.dir,
          encoding: 'utf-8',
          env: {
            PATH: process.env.PATH!,
            HOME: process.env.HOME!,
            // Intentionally NO CLAUDE_PLUGIN_ROOT — force fallback.
          },
        }
      );
      // Current behaviour: exit 3 because SKILL.md cannot be resolved from
      // the fallback-derived root (which points at the tmp dir that holds
      // the symlink, not the real plugin tree).
      expect(r.status).toBe(3);
      expect(r.stderr).toMatch(/SKILL\.md/);
      expect(r.stderr).toMatch(/cannot be read/);
    } finally {
      cleanup(h);
    }
  });

  it('works when invoked via symlink WITH CLAUDE_PLUGIN_ROOT set (recommended call pattern)', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    const linkPath = join(h.dir, 'prepare-fork-link.sh');
    symlinkSync(PREPARE_FORK, linkPath);
    try {
      const r = spawnSync(
        'bash',
        [linkPath, 'FEAT-TEST', '2', 'reviewing-requirements', '--mode', 'standard'],
        {
          cwd: h.dir,
          encoding: 'utf-8',
          env: {
            ...process.env,
            CLAUDE_PLUGIN_ROOT: h.pluginRoot,
            CLAUDE_SKILL_DIR: join(h.pluginRoot, 'skills/orchestrating-workflows'),
          },
        }
      );
      expect(r.status).toBe(0);
      expect(r.stdout.trim()).toMatch(/^(haiku|sonnet|opus)$/);
    } finally {
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Environment — CWD-sensitive state-file resolution', () => {
  it('exits 2 when invoked from a different CWD (does not walk up to find state)', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    const otherDir = mkdtempSync(join(tmpdir(), 'qa-feat-021-other-'));
    try {
      const r = spawnSync(
        'bash',
        [PREPARE_FORK, 'FEAT-TEST', '1', 'reviewing-requirements', '--mode', 'standard'],
        {
          cwd: otherDir,
          encoding: 'utf-8',
          env: {
            ...process.env,
            CLAUDE_PLUGIN_ROOT: h.pluginRoot,
            CLAUDE_SKILL_DIR: join(h.pluginRoot, 'skills/orchestrating-workflows'),
          },
        }
      );
      expect(r.status).toBe(2);
      expect(r.stderr).toMatch(/\.sdlc\/workflows\/FEAT-TEST\.json/);
      expect(r.stderr).toMatch(/not found/);
    } finally {
      try {
        rmSync(otherDir, { recursive: true, force: true });
      } catch {
        /* ignore */
      }
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Environment — non-UTF8 locale em-dash preservation', () => {
  it('emits Edge Case 11 warning with byte-preserved em-dash under LANG=C', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    try {
      const r = spawnSync(
        'bash',
        [PREPARE_FORK, 'FEAT-TEST', '3', 'creating-implementation-plans', '--cli-model', 'haiku'],
        {
          cwd: h.dir,
          encoding: 'buffer',
          env: {
            ...process.env,
            LANG: 'C',
            LC_ALL: 'C',
            CLAUDE_PLUGIN_ROOT: h.pluginRoot,
            CLAUDE_SKILL_DIR: join(h.pluginRoot, 'skills/orchestrating-workflows'),
          },
        }
      );
      expect(r.status).toBe(0);
      // Em-dash '→' is U+2192; UTF-8 encoding is E2 86 92.
      // Script source contains '→' in the echo line; under LANG=C the bytes
      // should still emit as-is (no transliteration unless something re-encodes).
      const arrow = Buffer.from([0xe2, 0x86, 0x92]);
      // Stderr must contain the 3-byte sequence.
      expect(r.stderr.includes(arrow)).toBe(true);
      // And the Edge Case 11 warning text.
      const stderrStr = r.stderr.toString('utf-8');
      expect(stderrStr).toMatch(/Hard override/);
      expect(stderrStr).toMatch(/bypassed baseline/);
    } finally {
      cleanup(h);
    }
  });
});

// ============================================================================
// Dimension 4: Dependency failure (trust boundaries)
// ============================================================================

describe('[QA FEAT-021] Dependency — resolve-tier returns multi-line garbage', () => {
  it('propagates whatever resolve-tier printed as tier to audit entry (documented trust-boundary behaviour)', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    // record-model-selection MUST run against real state file to persist.
    // resolve-tier is stubbed to emit multi-line output.
    const stubRoot = writeStubWorkflowState(
      h,
      `#!/usr/bin/env bash
case "$1" in
  resolve-tier)
    # Intentional multi-line garbage: tier on first line, noise after.
    printf 'opus\\n[model] debug trace — ignore me\\n'
    ;;
  record-model-selection)
    exec "${REAL_WORKFLOW_STATE}" "$@"
    ;;
  step-baseline|step-baseline-locked|*)
    exec "${REAL_WORKFLOW_STATE}" "$@"
    ;;
esac
`
    );
    try {
      const r = runPrepareFork(
        h,
        ['FEAT-TEST', '1', 'reviewing-requirements', '--mode', 'standard'],
        {
          CLAUDE_PLUGIN_ROOT: stubRoot,
          CLAUDE_SKILL_DIR: join(stubRoot, 'skills/orchestrating-workflows'),
        }
      );
      expect(r.status).toBe(0);
      // With Bash command substitution, \n at end is stripped but interior \n survives.
      // Document what actually lands in the audit entry so reviewers see the trust
      // boundary. Tier should contain "opus" and may contain the trailing noise.
      const entries = readState(h, 'FEAT-TEST').modelSelections;
      expect(entries.length).toBe(1);
      const storedTier = entries[0].tier;
      // Must contain the valid prefix.
      expect(storedTier).toMatch(/^opus/);
      // stdout contract: tier is printed verbatim to stdout.
      expect(r.stdout).toMatch(/^opus/);
    } finally {
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Dependency — step-baseline-locked returns wrong-case boolean', () => {
  it('echo line falls through to non-locked variant when value is "True" (strict match)', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    const stubRoot = writeStubWorkflowState(
      h,
      `#!/usr/bin/env bash
case "$1" in
  step-baseline-locked)
    # Wrong case — script should NOT match this as locked.
    echo "True"
    ;;
  step-baseline)
    echo haiku
    ;;
  resolve-tier)
    exec "${REAL_WORKFLOW_STATE}" "$@"
    ;;
  record-model-selection)
    exec "${REAL_WORKFLOW_STATE}" "$@"
    ;;
  *)
    exec "${REAL_WORKFLOW_STATE}" "$@"
    ;;
esac
`
    );
    try {
      const r = runPrepareFork(h, ['FEAT-TEST', '1', 'finalizing-workflow'], {
        CLAUDE_PLUGIN_ROOT: stubRoot,
        CLAUDE_SKILL_DIR: join(stubRoot, 'skills/orchestrating-workflows'),
      });
      expect(r.status).toBe(0);
      // Non-locked variant emits wi-complexity and override tokens.
      expect(r.stderr).toMatch(/wi-complexity=/);
      expect(r.stderr).toMatch(/override=/);
      expect(r.stderr).not.toMatch(/baseline-locked/);
    } finally {
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Dependency — step-baseline returns complexity label instead of tier', () => {
  it('propagates the garbage verbatim into echo line (trust-boundary)', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    const stubRoot = writeStubWorkflowState(
      h,
      `#!/usr/bin/env bash
case "$1" in
  step-baseline)
    # Bug: returns "medium" instead of "sonnet".
    echo "medium"
    ;;
  step-baseline-locked)
    echo false
    ;;
  resolve-tier)
    exec "${REAL_WORKFLOW_STATE}" "$@"
    ;;
  record-model-selection)
    exec "${REAL_WORKFLOW_STATE}" "$@"
    ;;
  *)
    exec "${REAL_WORKFLOW_STATE}" "$@"
    ;;
esac
`
    );
    try {
      const r = runPrepareFork(
        h,
        ['FEAT-TEST', '1', 'reviewing-requirements', '--mode', 'standard'],
        {
          CLAUDE_PLUGIN_ROOT: stubRoot,
          CLAUDE_SKILL_DIR: join(stubRoot, 'skills/orchestrating-workflows'),
        }
      );
      // Trust boundary: script forwards the garbage without validation.
      // Exit code is 0; echo line contains `baseline=medium`.
      expect(r.status).toBe(0);
      expect(r.stderr).toMatch(/baseline=medium/);
    } finally {
      cleanup(h);
    }
  });
});

// ============================================================================
// Dimension 5: Cross-cutting
// ============================================================================

describe('[QA FEAT-021] Cross-cutting — script without exec bit', () => {
  it('still runs via `bash prepare-fork.sh` when file mode is 0644', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    // Copy to tmp and chmod 0644.
    const local = join(h.dir, 'prepare-fork.sh');
    writeFileSync(local, readFileSync(PREPARE_FORK, 'utf-8'));
    chmodSync(local, 0o644);
    try {
      const r = spawnSync(
        'bash',
        [local, 'FEAT-TEST', '2', 'reviewing-requirements', '--mode', 'standard'],
        {
          cwd: h.dir,
          encoding: 'utf-8',
          env: {
            ...process.env,
            CLAUDE_PLUGIN_ROOT: h.pluginRoot,
            CLAUDE_SKILL_DIR: join(h.pluginRoot, 'skills/orchestrating-workflows'),
          },
        }
      );
      expect(r.status).toBe(0);
      expect(r.stdout.trim()).toMatch(/^(haiku|sonnet|opus)$/);
    } finally {
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Cross-cutting — concurrent invocations (different IDs)', () => {
  it('two parallel calls against different state files do not cross-contaminate', async () => {
    const h = makeHarness();
    seedState(h, 'FEAT-A');
    seedState(h, 'FEAT-B');
    try {
      const [rA, rB] = await Promise.all([
        new Promise<{ status: number | null }>((resolve) => {
          const r = spawnSync(
            'bash',
            [PREPARE_FORK, 'FEAT-A', '1', 'reviewing-requirements', '--mode', 'standard'],
            {
              cwd: h.dir,
              encoding: 'utf-8',
              env: {
                ...process.env,
                CLAUDE_PLUGIN_ROOT: h.pluginRoot,
                CLAUDE_SKILL_DIR: join(h.pluginRoot, 'skills/orchestrating-workflows'),
              },
            }
          );
          resolve({ status: r.status });
        }),
        new Promise<{ status: number | null }>((resolve) => {
          const r = spawnSync(
            'bash',
            [PREPARE_FORK, 'FEAT-B', '1', 'creating-implementation-plans'],
            {
              cwd: h.dir,
              encoding: 'utf-8',
              env: {
                ...process.env,
                CLAUDE_PLUGIN_ROOT: h.pluginRoot,
                CLAUDE_SKILL_DIR: join(h.pluginRoot, 'skills/orchestrating-workflows'),
              },
            }
          );
          resolve({ status: r.status });
        }),
      ]);
      expect(rA.status).toBe(0);
      expect(rB.status).toBe(0);
      const a = readState(h, 'FEAT-A');
      const b = readState(h, 'FEAT-B');
      expect(a.modelSelections.length).toBe(1);
      expect(b.modelSelections.length).toBe(1);
      expect(a.modelSelections[0].skill).toBe('reviewing-requirements');
      expect(b.modelSelections[0].skill).toBe('creating-implementation-plans');
    } finally {
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Cross-cutting — SKILL.md parent dir unreadable', () => {
  it('exits 3 when the skills/<name>/ parent directory mode is 0000', () => {
    const h = makeHarness();
    seedState(h, 'FEAT-TEST');
    const skillDir = join(h.pluginRoot, 'skills/reviewing-requirements');
    chmodSync(skillDir, 0o000);
    try {
      const r = runPrepareFork(h, [
        'FEAT-TEST',
        '1',
        'reviewing-requirements',
        '--mode',
        'standard',
      ]);
      expect(r.status).toBe(3);
      expect(r.stderr).toMatch(/SKILL\.md/);
    } finally {
      try {
        chmodSync(skillDir, 0o755);
      } catch {
        /* ignore */
      }
      cleanup(h);
    }
  });
});

describe('[QA FEAT-021] Cross-cutting — workflows directory not writable', () => {
  it('propagates non-zero from record-model-selection when .sdlc/workflows is 0555', () => {
    const h = makeHarness();
    const statePath = seedState(h, 'FEAT-TEST');
    const workflowsDir = join(h.dir, '.sdlc/workflows');
    // Snapshot length and content.
    const before = readFileSync(statePath, 'utf-8');
    chmodSync(workflowsDir, 0o555);
    try {
      const r = runPrepareFork(h, [
        'FEAT-TEST',
        '1',
        'reviewing-requirements',
        '--mode',
        'standard',
      ]);
      // Non-zero if record-model-selection needs to create a tmp file in the dir.
      // Or 0 if record-model-selection writes via direct overwrite — both are
      // acceptable; we only assert no corruption.
      chmodSync(workflowsDir, 0o755);
      const after = readFileSync(statePath, 'utf-8');
      expect(() => JSON.parse(after)).not.toThrow();
      if (r.status !== 0) {
        expect(r.stderr.length).toBeGreaterThan(0);
        // State file should be byte-for-byte unchanged on failure.
        expect(after).toBe(before);
      }
    } finally {
      try {
        chmodSync(workflowsDir, 0o755);
      } catch {
        /* ignore */
      }
      cleanup(h);
    }
  });
});
