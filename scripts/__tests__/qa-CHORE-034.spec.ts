import { describe, it, expect } from 'vitest';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

// ---------------------------------------------------------------------------
// CHORE-034 adversarial QA — documentation-contract regression suite.
//
// This chore is documentation-only: it installs an Output Style directive and
// a fork-to-orchestrator return contract in the orchestrating-workflows
// SKILL.md, and it adds contract-pointer breadcrumbs to each fork-invocation
// spec in references/step-execution-details.md. There is no new parser, so
// the adversarial surface is:
//
//   * documented format vs. actual emitter (FR-14 echo arrow character — the
//     review-flagged pre-merge blocker)
//   * documentation integrity of the canonical contract shapes
//   * presence of every load-bearing carve-out (regression guard so a future
//     rewrite cannot silently drop one)
//   * fork-invocation specs all reference the contract (per AC #4)
//   * backwards compatibility: pre-CHORE-034 state files still parse, and the
//     existing `Found **N errors**, ...` findings-summary regex still matches
//     its canonical line (so reviewing-requirements forks are unaffected).
// ---------------------------------------------------------------------------

const REPO_ROOT = process.cwd();
const ORCH_DIR = join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/skills/orchestrating-workflows'
);
const SKILL_MD = join(ORCH_DIR, 'SKILL.md');
const STEP_EXEC_MD = join(ORCH_DIR, 'references/step-execution-details.md');
const CHAIN_PROC_MD = join(ORCH_DIR, 'references/chain-procedures.md');
const PREPARE_FORK = join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/scripts/prepare-fork.sh'
);

function readSkill(): string {
  return readFileSync(SKILL_MD, 'utf8');
}

// ---------- Inputs dimension ----------

describe('[QA CHORE-034] Inputs: Output Style section documentation integrity', () => {
  it('SKILL.md contains the `## Output Style` section', () => {
    const body = readSkill();
    expect(body).toMatch(/^## Output Style$/m);
  });

  it('Output Style section is placed after Quick Start (early-read governance)', () => {
    const body = readSkill();
    const quickStart = body.indexOf('## Quick Start');
    const outputStyle = body.indexOf('## Output Style');
    const featureChain = body.indexOf('## Feature Chain Step Sequence');
    expect(quickStart).toBeGreaterThan(-1);
    expect(outputStyle).toBeGreaterThan(quickStart);
    expect(outputStyle).toBeLessThan(featureChain);
  });

  it('Output Style declares all three subsections', () => {
    const body = readSkill();
    expect(body).toMatch(/### Lite narration rules/);
    expect(body).toMatch(/### Load-bearing carve-outs \(never strip\)/);
    expect(body).toMatch(/### Fork-to-orchestrator return contract/);
  });

  it('Three canonical fork-return shapes are all documented', () => {
    const body = readSkill();
    // Shape 1: done success
    expect(body).toMatch(/`done \| artifact=<path> \| <note-of-at-most-10-words>`/);
    // Shape 2: failed
    expect(body).toMatch(/`failed \| <one-sentence reason>`/);
    // Shape 3: reviewing-requirements findings summary (retained shape)
    expect(body).toMatch(
      /`Found \*\*N errors\*\*, \*\*N warnings\*\*, \*\*N info\*\*`/
    );
  });

  it('contract explicitly disambiguates reviewing-requirements (resolves contract-ambiguity cross-cutting CX-P0 #2)', () => {
    const body = readSkill();
    expect(body).toMatch(
      /`reviewing-requirements` does not emit the `done \| \.\.\.` shape/
    );
  });

  it('contract precedence over lite rules is stated explicitly', () => {
    const body = readSkill();
    expect(body).toMatch(
      /the return contract takes precedence over the lite rules/i
    );
  });
});

// ---------- Cross-cutting dimension ----------

describe('[QA CHORE-034] Cross-cutting: load-bearing carve-outs regression guard', () => {
  // Each entry is a regex that the carve-out list must match. Kept terse so
  // minor prose edits don't break the test, but strict enough to catch silent
  // deletion of an entry.
  const requiredCarveouts: Array<[string, RegExp]> = [
    ['fail errors', /\*\*Error messages from `fail` calls\*\*/],
    ['security warnings', /\*\*Security-sensitive warnings\*\*/],
    ['interactive prompts', /\*\*Interactive prompts\*\*/],
    [
      'findings display',
      /\*\*Findings display from `reviewing-requirements`\*\*/,
    ],
    ['FR-14 echo', /\*\*FR-14 console echo lines\*\*/],
    ['tagged structured logs', /\*\*Tagged structured logs\*\*/],
    ['state transitions', /\*\*User-visible state transitions\*\*/],
  ];

  for (const [label, re] of requiredCarveouts) {
    it(`carve-out preserved: ${label}`, () => {
      const body = readSkill();
      expect(body).toMatch(re);
    });
  }

  it('findings display carve-out forbids truncation (required for findings-decision informed consent)', () => {
    const body = readSkill();
    expect(body).toMatch(
      /full findings list must be shown to the user before any findings-decision prompt.*Do not truncate/is
    );
  });
});

// ---------- Inputs dimension: FR-14 echo consistency (the review-flagged blocker) ----------

describe('[QA CHORE-034] Inputs: FR-14 echo documented format matches prepare-fork.sh emitter', () => {
  it('SKILL.md documents the FR-14 echo with Unicode right-arrow (U+2192)', () => {
    const body = readSkill();
    // The carve-out example must use → (U+2192), not ASCII "->".
    // Regression guard for the CHORE-034 code-review fix.
    const carveoutLine = body.match(
      /\*\*FR-14 console echo lines\*\*[^\n]*/
    )?.[0];
    expect(carveoutLine).toBeDefined();
    expect(carveoutLine).toContain('→');
    expect(carveoutLine).not.toMatch(/->\s*\{tier\}/);
  });

  it('prepare-fork.sh emitter uses Unicode → in every FR-14 step-echo', () => {
    const src = readFileSync(PREPARE_FORK, 'utf8');
    // FR-14 echoes are the "[model] step N ..." lines that carry the resolved
    // tier. Other `[model] ...` lines (e.g., the Edge Case 11 baseline-bypass
    // warning) are not FR-14 echoes and do not need the arrow character.
    const fr14Lines = src.match(/echo "\[model\] step[^"]*"/g) ?? [];
    expect(fr14Lines.length).toBeGreaterThanOrEqual(2);
    for (const line of fr14Lines) {
      expect(line).toContain('→');
      expect(line).not.toMatch(/\s->\s/);
    }
  });

  it('ASCII-arrows rule carves out script-emitted structured logs', () => {
    const body = readSkill();
    // The lite rule must acknowledge the script-emitted exception so it does
    // not conflict with the FR-14 carve-out's Unicode format.
    expect(body).toMatch(
      /Script-emitted structured logs are out of scope for this rule/i
    );
  });

  it('prepare-fork.sh emitter format matches a live invocation', () => {
    // End-to-end: create a minimal state file, invoke prepare-fork.sh, and
    // assert the FR-14 echo on stderr matches the `→` format.
    const { mkdtempSync, writeFileSync, mkdirSync } = require('node:fs');
    const { tmpdir } = require('node:os');
    const workdir = mkdtempSync(join(tmpdir(), 'qa-chore-034-fr14-'));
    mkdirSync(join(workdir, '.sdlc/workflows'), { recursive: true });
    mkdirSync(join(workdir, 'requirements/chores'), { recursive: true });
    // Minimal state file for a chore workflow
    const stateId = 'CHORE-000';
    const state = {
      id: stateId,
      type: 'chore',
      currentStep: 0,
      status: 'in-progress',
      pauseReason: null,
      gate: null,
      steps: [
        { name: 'x', skill: 'x', context: 'main', status: 'pending', artifact: null, completedAt: null },
        { name: 'Review requirements (standard)', skill: 'reviewing-requirements', context: 'fork', status: 'pending', artifact: null, completedAt: null },
      ],
      phases: { total: 0, completed: 0 },
      prNumber: null,
      branch: null,
      startedAt: '2026-04-21T00:00:00Z',
      lastResumedAt: null,
      complexity: 'medium',
      complexityStage: 'init',
      modelOverride: null,
      modelSelections: [],
    };
    writeFileSync(
      join(workdir, `.sdlc/workflows/${stateId}.json`),
      JSON.stringify(state, null, 2)
    );
    const res = spawnSync(
      'bash',
      [PREPARE_FORK, stateId, '1', 'reviewing-requirements', '--mode', 'standard'],
      { cwd: workdir, encoding: 'utf8' }
    );
    expect(res.status).toBe(0);
    // FR-14 echo is on stderr; tier is on stdout
    expect(res.stderr).toContain('→');
    expect(res.stderr).not.toMatch(/->\s+sonnet/);
    expect(res.stderr).toMatch(/\[model\] step 1 \(reviewing-requirements, mode=standard\) → sonnet/);
  });
});

// ---------- Cross-cutting dimension: fork-invocation spec breadcrumbs (AC #4) ----------

describe('[QA CHORE-034] Cross-cutting: every fork-invocation spec points to the contract', () => {
  it('step-execution-details.md has a leading contract-shape summary', () => {
    const body = readFileSync(STEP_EXEC_MD, 'utf8');
    expect(body).toMatch(
      /Every fork site below expects the subagent to return the canonical contract shape/i
    );
  });

  // Each named fork site must have a pointer — the exact phrasing is enforced
  // as a substring so prose edits don't break the test as long as the pointer
  // remains reachable from each spec.
  const forkSites = [
    // Feature chain
    'Step 2 — `reviewing-requirements` (standard review)',
    'Step 3 — `creating-implementation-plans`',
    'Step 5+N+4 — `finalizing-workflow`',
  ];

  for (const site of forkSites) {
    it(`fork site "${site}" carries a canonical-contract pointer`, () => {
      const body = readFileSync(STEP_EXEC_MD, 'utf8');
      // Locate the site heading line and walk forward up to the next blank
      // line block; the pointer must appear within the spec paragraph.
      const idx = body.indexOf(site);
      expect(idx).toBeGreaterThan(-1);
      // Look at the 800-char window following the site name
      const window = body.slice(idx, idx + 800);
      expect(window).toMatch(
        /canonical contract shape.*Output Style/is
      );
    });
  }
});

// ---------- State transitions dimension: state-file schema compat (SC-P0) ----------

describe('[QA CHORE-034] State transitions: state-file schema backwards compatibility', () => {
  it('live CHORE-034 state file parses and carries all post-FEAT-014 fields', () => {
    const statePath = join(REPO_ROOT, '.sdlc/workflows/CHORE-034.json');
    expect(existsSync(statePath)).toBe(true);
    const parsed = JSON.parse(readFileSync(statePath, 'utf8')) as Record<
      string,
      unknown
    >;
    // Core schema
    expect(parsed.id).toBe('CHORE-034');
    expect(parsed.type).toBe('chore');
    expect(Array.isArray(parsed.steps)).toBe(true);
    // FEAT-014 additions (must survive the pilot — the chore promised "no
    // behavioral changes")
    expect(parsed.complexity).toBeDefined();
    expect(parsed.complexityStage).toBeDefined();
    expect(parsed.modelSelections).toBeDefined();
    expect(Array.isArray(parsed.modelSelections)).toBe(true);
  });

  it('previous workflow state files (pre-CHORE-034) still parse without migration', () => {
    const wfDir = join(REPO_ROOT, '.sdlc/workflows');
    const entries = readdirSync(wfDir).filter(
      (f) => f.match(/^(FEAT|CHORE|BUG)-\d+\.json$/) && f !== 'CHORE-034.json'
    );
    expect(entries.length).toBeGreaterThan(0);
    for (const entry of entries) {
      const body = readFileSync(join(wfDir, entry), 'utf8');
      expect(() => JSON.parse(body)).not.toThrow();
      const parsed = JSON.parse(body) as Record<string, unknown>;
      expect(parsed.id).toBeDefined();
      expect(parsed.type).toBeDefined();
      expect(Array.isArray(parsed.steps)).toBe(true);
    }
  });
});

// ---------- Inputs dimension: findings-summary regex (I-P0 #2) ----------

describe('[QA CHORE-034] Inputs: reviewing-requirements findings-summary regex is preserved', () => {
  // The orchestrator documents this regex for parsing the findings count line.
  // The pilot did not change the parser; this test guards that the documented
  // shape still matches its canonical line after any lite-rule edits.
  const summaryRegex = /Found \*\*(\d+) errors\*\*, \*\*(\d+) warnings\*\*, \*\*(\d+) info\*\*/;

  it('canonical summary line matches the documented shape', () => {
    const canonical =
      'Standard review for CHORE-034: Found **0 errors**, **2 warnings**, **3 info** in requirements/chores/CHORE-034.md';
    const match = canonical.match(summaryRegex);
    expect(match).not.toBeNull();
    expect(match?.[1]).toBe('0');
    expect(match?.[2]).toBe('2');
    expect(match?.[3]).toBe('3');
  });

  it('regex is anchored on the substring, not line-start (per SKILL.md note)', () => {
    // Test-plan-reconciliation output prefixes the mode to the line.
    const prefixed =
      'Test-plan reconciliation for FEAT-042: Found **1 errors**, **0 warnings**, **4 info**';
    const match = prefixed.match(summaryRegex);
    expect(match).not.toBeNull();
    expect(match?.[1]).toBe('1');
  });

  it('zero-findings sentinel is distinguishable from a missing summary line', () => {
    const zero =
      'Standard review for CHORE-034: No issues found in requirements/chores/CHORE-034.md';
    expect(zero.match(summaryRegex)).toBeNull();
    expect(zero).toContain('No issues found');
  });
});

// ---------- Environment dimension: npm run validate + npm test are exercised by CI,
// but spot-checks here guard that the SKILL.md is still parseable. ----------

describe('[QA CHORE-034] Environment: SKILL.md structural integrity', () => {
  it('SKILL.md still starts with valid YAML frontmatter', () => {
    const body = readSkill();
    expect(body.startsWith('---\n')).toBe(true);
    // The frontmatter must end before the Output Style section so it wasn't
    // accidentally moved.
    const frontmatterEnd = body.indexOf('\n---\n', 4);
    expect(frontmatterEnd).toBeGreaterThan(0);
    expect(frontmatterEnd).toBeLessThan(body.indexOf('## Output Style'));
  });

  it('chain-procedures.md unchanged procedurally (only transitional prose tightened)', () => {
    const body = readFileSync(CHAIN_PROC_MD, 'utf8');
    // Smoke: all three chain procedures must still be present after the
    // lite-rule edits, and the Resume Procedure anchor must still exist.
    expect(body).toMatch(/## New Feature Workflow Procedure/);
    expect(body).toMatch(/## New Chore Workflow Procedure/);
    expect(body).toMatch(/## New Bug Workflow Procedure/);
    expect(body).toMatch(/## Resume Procedure/);
  });
});
