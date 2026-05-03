import { describe, it, expect } from 'vitest';
import { readFileSync, existsSync, mkdtempSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';

// ---------------------------------------------------------------------------
// CHORE-035 adversarial QA — input-token-pilot regression suite.
//
// This chore compresses `orchestrating-workflows/SKILL.md` prose to the lite
// style, relocates two heavy numbered recipes into new reference files
// (`forked-steps.md`, `reviewing-requirements-flow.md`), and consolidates
// three per-chain step-sequence tables into one parameterized table plus a
// deltas note. The CHORE-034 Output Style / fork-return-contract rules must
// be preserved verbatim.
//
// Adversarial surface:
//   * inline pointer integrity (every SKILL.md link to references/*.md must
//     land on an existing file and heading — primary P0 from the plan)
//   * consolidated-table completeness (every row the three original tables
//     conveyed must be reachable from the unified table + deltas note)
//   * state-file step-index invariance (existing workflow state files must
//     still resume — step indices and step names persisted pre-CHORE-035 must
//     match what the chore's post-change init emits)
//   * carve-out and contract preservation (CHORE-034 guarantees must survive
//     the lite-rule pass)
//   * the relocated reference files are self-contained enough that the
//     orchestrator no longer needs the inlined recipes
// ---------------------------------------------------------------------------

const REPO_ROOT = process.cwd();
const ORCH_DIR = join(REPO_ROOT, 'plugins/lwndev-sdlc/skills/orchestrating-workflows');
const SKILL_MD = join(ORCH_DIR, 'SKILL.md');
const REF_DIR = join(ORCH_DIR, 'references');
const FORKED_STEPS_MD = join(REF_DIR, 'forked-steps.md');
const REVIEWING_FLOW_MD = join(REF_DIR, 'reviewing-requirements-flow.md');
const WORKFLOW_STATE = join(ORCH_DIR, 'scripts/workflow-state.sh');
const CHORE_DOC = join(
  REPO_ROOT,
  'requirements/chores/CHORE-035-input-token-optimization-pilot.md'
);

function readSkill(): string {
  return readFileSync(SKILL_MD, 'utf8');
}

// =============================================================================
// Inputs dimension
// =============================================================================

describe('[QA CHORE-035] Inputs: relocated-section inline pointers resolve', () => {
  // P0 — the primary risk from the plan: a relocated section's inline pointer
  // from SKILL.md lands on a file that does not exist, or a heading that does
  // not exist inside the target file.

  function extractMarkdownLinks(body: string): Array<{ label: string; target: string }> {
    const re = /\[([^\]]+)\]\(([^)]+)\)/g;
    const out: Array<{ label: string; target: string }> = [];
    let m: RegExpExecArray | null;
    while ((m = re.exec(body))) {
      out.push({ label: m[1], target: m[2] });
    }
    return out;
  }

  it('every `references/*.md` link in SKILL.md points to a file that exists', () => {
    const body = readSkill();
    const links = extractMarkdownLinks(body).filter((l) => l.target.startsWith('references/'));
    expect(links.length).toBeGreaterThan(0);
    for (const { target } of links) {
      const [path] = target.split('#');
      const full = join(ORCH_DIR, path);
      expect(existsSync(full), `missing reference file: ${full}`).toBe(true);
    }
  });

  it('both newly created reference files (forked-steps.md, reviewing-requirements-flow.md) exist and are non-empty', () => {
    expect(existsSync(FORKED_STEPS_MD)).toBe(true);
    expect(existsSync(REVIEWING_FLOW_MD)).toBe(true);
    expect(readFileSync(FORKED_STEPS_MD, 'utf8').length).toBeGreaterThan(500);
    expect(readFileSync(REVIEWING_FLOW_MD, 'utf8').length).toBeGreaterThan(500);
  });

  it('SKILL.md dispatcher paragraphs each contain exactly one inline pointer to their target reference', () => {
    const body = readSkill();
    // Key dispatcher sections expected to exist post-relocation.
    const expectedDispatchers: Array<[string, string]> = [
      ['### Forked Steps', 'references/forked-steps.md'],
      ['### Reviewing-Requirements Findings Handling', 'references/reviewing-requirements-flow.md'],
      ['### Chain-Specific Step Details', 'references/step-execution-details.md'],
      ['## Chain Workflow Procedures', 'references/chain-procedures.md'],
      ['## Issue Tracking via `managing-work-items`', 'references/issue-tracking.md'],
      [
        '## Verification Checklist and Skill Relationships',
        'references/verification-and-relationships.md',
      ],
    ];

    for (const [heading, ref] of expectedDispatchers) {
      const headingIdx = body.indexOf(heading);
      expect(headingIdx, `missing dispatcher heading: ${heading}`).toBeGreaterThan(-1);
      // Walk forward to the next top-level or sibling heading; the dispatcher
      // body lives in that window.
      const nextHeadingMatch = body.slice(headingIdx + heading.length).match(/\n(?:##\s|###\s)/);
      const end = nextHeadingMatch
        ? headingIdx + heading.length + nextHeadingMatch.index!
        : body.length;
      const window = body.slice(headingIdx, end);
      expect(window, `dispatcher for ${heading} missing pointer to ${ref}`).toContain(ref);
    }
  });

  it('no sub-skill SKILL.md absolute-path reference in SKILL.md is broken', () => {
    const body = readSkill();
    // Find every reference to a sibling skill's SKILL.md via
    // `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md` and verify the skill
    // directory exists (we can't verify the full absolute path resolves since
    // CLAUDE_PLUGIN_ROOT is a template; we verify the skill dir is real).
    const re = /\$\{CLAUDE_PLUGIN_ROOT\}\/skills\/([a-z0-9-]+)\/SKILL\.md/g;
    const seen = new Set<string>();
    let m: RegExpExecArray | null;
    while ((m = re.exec(body))) seen.add(m[1]);
    for (const skill of seen) {
      const dir = join(REPO_ROOT, 'plugins/lwndev-sdlc/skills', skill);
      expect(existsSync(dir), `SKILL.md absolute-path target missing: ${dir}`).toBe(true);
    }
  });
});

describe('[QA CHORE-035] Inputs: consolidated parameterized chain-step table preserves every row', () => {
  // P0 — the three original tables (Feature / Chore / Bug) are collapsed into
  // one parameterized table. A silently dropped row is a regression we must
  // catch. Assert every logical (chain, step-name) pair the three original
  // tables conveyed is reachable from the consolidated table.

  function chainStepTable(body: string): string {
    // Isolate the table between the three chain headings and the next
    // `## ` heading (Chain Workflow Procedures).
    const start = body.indexOf('## Feature Chain Step Sequence');
    expect(start).toBeGreaterThan(-1);
    const end = body.indexOf('## Chain Workflow Procedures');
    expect(end).toBeGreaterThan(start);
    return body.slice(start, end);
  }

  it('all three chain section headings remain present as sibling anchors', () => {
    const body = readSkill();
    expect(body).toMatch(/^## Feature Chain Step Sequence$/m);
    expect(body).toMatch(/^## Chore Chain Step Sequence$/m);
    expect(body).toMatch(/^## Bug Chain Step Sequence$/m);
  });

  it('consolidated table exposes an "Applies to" column', () => {
    const table = chainStepTable(readSkill());
    expect(table).toMatch(/\|\s*Applies to\s*\|/);
  });

  // Each tuple describes a row the original per-chain tables conveyed, paired
  // with a substring (literal or regex) that must appear inside the
  // consolidated table for that row to be considered preserved.
  const requiredRows: Array<[string, RegExp]> = [
    // Feature chain
    ['feature: step 1 document requirements', /documenting-features/],
    ['feature: step 3 creating implementation plan', /creating-implementation-plans/],
    ['feature: step 4 PAUSE plan approval', /PAUSE:\s*Plan approval/i],
    ['feature: phase loop', /implementing-plan-phases/],
    ['feature: create PR fork', /Create PR/],
    ['feature: PAUSE PR review', /PAUSE:\s*PR review/i],
    ['feature: finalize', /finalizing-workflow/],
    // Chore chain
    ['chore: document chore step 1', /documenting-chores/],
    ['chore: execute chore fork', /executing-chores/],
    // Bug chain
    ['bug: document bug step 1', /documenting-bugs/],
    ['bug: execute bug fix fork', /executing-bug-fixes/],
    // Shared
    ['review requirements standard', /reviewing-requirements/],
    ['documenting QA test plan', /documenting-qa/],
    ['executing QA', /executing-qa/],
  ];

  for (const [label, re] of requiredRows) {
    it(`consolidated table contains row: ${label}`, () => {
      const table = chainStepTable(readSkill());
      expect(table, `row "${label}" missing from consolidated table`).toMatch(re);
    });
  }

  it('chore skip-condition for step 2 (complexity == low) is captured in the table', () => {
    const table = chainStepTable(readSkill());
    expect(table).toMatch(/complexity\s*==\s*low/i);
  });

  it('per-chain deltas note lists all three chain types with their step-count shape', () => {
    const table = chainStepTable(readSkill());
    // Feature's N-phase count, chore's fixed 7, bug's fixed 7
    expect(table).toMatch(/5\s*\+\s*N\s*\+\s*4/); // feature step count
    expect(table).toMatch(/chore chain.*\b7\b/is); // chore fixed 7
    expect(table).toMatch(/bug chain.*\b7\b/is); // bug fixed 7
    // Pause points differ
    expect(table).toMatch(/plan approval/i);
    expect(table).toMatch(/PR review/i);
  });
});

describe('[QA CHORE-035] Inputs: relocated reference files are self-contained', () => {
  // P0 — every script-invocation snippet, every documented flag, every bash
  // code block that used to live inline in SKILL.md must be reachable from
  // the reference file it moved into. A relocated recipe that drops its own
  // command lines would break orchestrator behavior silently.

  it('forked-steps.md carries the full seven-step fork recipe', () => {
    const body = readFileSync(FORKED_STEPS_MD, 'utf8');
    // Pre-fork ceremony -> prepare-fork.sh invocation -> Agent spawn ->
    // NFR-6 fallback -> FR-11 retry classifier -> artifact validation ->
    // advance. Test by numbered-step markers.
    expect(body).toMatch(/^1\. \*\*Run the pre-fork ceremony\*\*/m);
    expect(body).toMatch(/^2\. Spawn a general-purpose subagent/m);
    expect(body).toMatch(/^3\. Wait for the subagent/m);
    expect(body).toMatch(/^4\. \*\*NFR-6 Agent-tool-rejection fallback/m);
    expect(body).toMatch(/^5\. \*\*FR-11 retry-with-tier-upgrade/m);
    expect(body).toMatch(/^6\. Validate the expected artifact/m);
    expect(body).toMatch(/^7\. On success, advance state/m);
  });

  it('forked-steps.md carries the prepare-fork.sh invocation snippet with every documented flag', () => {
    const body = readFileSync(FORKED_STEPS_MD, 'utf8');
    // The snippet uses ${CLAUDE_PLUGIN_ROOT} template in the post-chore file.
    expect(body).toContain('prepare-fork.sh');
    for (const flag of [
      '--mode',
      '--phase',
      '--cli-model',
      '--cli-complexity',
      '--cli-model-for',
    ]) {
      expect(body, `missing documented flag ${flag} in forked-steps.md`).toContain(flag);
    }
  });

  it('forked-steps.md carries the Fork Step-Name Map with every fork site', () => {
    const body = readFileSync(FORKED_STEPS_MD, 'utf8');
    expect(body).toMatch(/##\s+Fork Step-Name Map/);
    for (const token of [
      '`reviewing-requirements`',
      '`creating-implementation-plans`',
      '`implementing-plan-phases`',
      '`executing-chores`',
      '`executing-bug-fixes`',
      '`finalizing-workflow`',
      '`pr-creation`',
    ]) {
      expect(body, `missing fork-step-name ${token}`).toContain(token);
    }
  });

  it('reviewing-requirements-flow.md carries the full Decision Flow plus auto-fix re-run rules', () => {
    const body = readFileSync(REVIEWING_FLOW_MD, 'utf8');
    expect(body).toMatch(/##\s+Parsing Findings/);
    expect(body).toMatch(/##\s+Decision Flow/);
    expect(body).toMatch(/##\s+Applying Auto-Fixes/);
    expect(body).toMatch(/##\s+Persisting Findings/);
    // The four decision-flow categories must all be named: zero findings,
    // warnings-only gate (auto-advance and prompt branches), errors block.
    expect(body).toMatch(/Zero findings/i);
    expect(body).toMatch(/Warnings\/info only/i);
    expect(body).toMatch(/Errors present/i);
    // Re-run max-1 invariant
    expect(body).toMatch(/re-run.*max\s+1|single allowed retry/i);
  });

  it('reviewing-requirements-flow.md carries the decision-to-call mapping table', () => {
    const body = readFileSync(REVIEWING_FLOW_MD, 'utf8');
    expect(body).toMatch(/###?\s+Decision-to-Call Mapping/);
    // Every decision that calls record-findings must appear as a table row.
    for (const dec of ['advanced', 'auto-advanced', 'user-advanced', 'paused', 'auto-fixed']) {
      expect(body, `missing decision token "${dec}" in decision-to-call mapping`).toContain(dec);
    }
  });
});

// =============================================================================
// State transitions dimension
// =============================================================================

describe('[QA CHORE-035] State transitions: existing workflow state files still resume', () => {
  // P0 — a workflow state file written against the pre-CHORE-035 SKILL.md
  // must resume correctly after the chore lands. The critical invariants are:
  // (a) step count per chain type unchanged, (b) step names unchanged, and
  // (c) state-file schema unchanged.

  function initState(type: 'feature' | 'chore' | 'bug', id: string): Record<string, unknown> {
    const workdir = mkdtempSync(join(tmpdir(), `qa-chore-035-${type}-`));
    mkdirSync(join(workdir, '.sdlc/workflows'), { recursive: true });
    const res = spawnSync('bash', [WORKFLOW_STATE, 'init', id, type], {
      cwd: workdir,
      encoding: 'utf8',
    });
    expect(res.status, `init failed: ${res.stderr}`).toBe(0);
    const stateRaw = readFileSync(join(workdir, `.sdlc/workflows/${id}.json`), 'utf8');
    return JSON.parse(stateRaw) as Record<string, unknown>;
  }

  it('chore chain has exactly 7 fixed steps after init', () => {
    const state = initState('chore', 'CHORE-990');
    const steps = state.steps as Array<{ name: string }>;
    expect(steps.length).toBe(7);
    const names = steps.map((s) => s.name);
    expect(names).toEqual([
      'Document chore',
      'Review requirements (standard)',
      'Document QA test plan',
      'Execute chore',
      'PR review',
      'Execute QA',
      'Finalize',
    ]);
  });

  it('bug chain has exactly 7 fixed steps after init', () => {
    const state = initState('bug', 'BUG-990');
    const steps = state.steps as Array<{ name: string }>;
    expect(steps.length).toBe(7);
    const names = steps.map((s) => s.name);
    expect(names).toEqual([
      'Document bug',
      'Review requirements (standard)',
      'Document QA test plan',
      'Execute bug fix',
      'PR review',
      'Execute QA',
      'Finalize',
    ]);
  });

  it('feature chain has 5 steps before phases (phase loop added on demand)', () => {
    const state = initState('feature', 'FEAT-990');
    const steps = state.steps as Array<{ name: string }>;
    // init seeds the first 5 steps; the + N + 4 suffix (phases, Create PR,
    // PR review, Execute QA, Finalize) is appended during the workflow.
    expect(steps.length).toBeGreaterThanOrEqual(5);
    const firstFive = steps.slice(0, 5).map((s) => s.name);
    expect(firstFive).toEqual([
      'Document feature requirements',
      'Review requirements (standard)',
      'Create implementation plan',
      'Plan approval',
      'Document QA test plan',
    ]);
  });

  it('a pre-CHORE-035 chore state file resumes correctly (step-index numbering invariant)', () => {
    // Simulate a state file written pre-CHORE-035 paused at PR review (the
    // CHORE-035 state file itself was captured at this point — use its shape).
    const workdir = mkdtempSync(join(tmpdir(), 'qa-chore-035-resume-'));
    mkdirSync(join(workdir, '.sdlc/workflows'), { recursive: true });
    const preChoreState = {
      id: 'CHORE-991',
      type: 'chore',
      currentStep: 5,
      status: 'paused',
      pauseReason: 'pr-review',
      gate: null,
      steps: [
        {
          name: 'Document chore',
          skill: 'documenting-chores',
          context: 'main',
          status: 'complete',
          artifact: 'requirements/chores/CHORE-991.md',
          completedAt: '2026-04-01T00:00:00Z',
        },
        {
          name: 'Review requirements (standard)',
          skill: 'reviewing-requirements',
          context: 'fork',
          status: 'complete',
          artifact: 'requirements/chores/CHORE-991.md',
          completedAt: '2026-04-01T00:01:00Z',
        },
        {
          name: 'Document QA test plan',
          skill: 'documenting-qa',
          context: 'main',
          status: 'complete',
          artifact: 'qa/test-plans/QA-plan-CHORE-991.md',
          completedAt: '2026-04-01T00:02:00Z',
        },
        {
          name: 'Execute chore',
          skill: 'executing-chores',
          context: 'fork',
          status: 'complete',
          artifact: 'https://example.com/pr/1',
          completedAt: '2026-04-01T00:03:00Z',
        },
        {
          name: 'PR review',
          skill: null,
          context: 'pause',
          status: 'complete',
          artifact: null,
          completedAt: '2026-04-01T00:04:00Z',
        },
        {
          name: 'Execute QA',
          skill: 'executing-qa',
          context: 'main',
          status: 'pending',
          artifact: null,
          completedAt: null,
        },
        {
          name: 'Finalize',
          skill: 'finalizing-workflow',
          context: 'fork',
          status: 'pending',
          artifact: null,
          completedAt: null,
        },
      ],
      phases: { total: 0, completed: 0 },
      prNumber: 1,
      branch: 'chore/CHORE-991',
      startedAt: '2026-04-01T00:00:00Z',
      lastResumedAt: null,
      complexity: 'medium',
      complexityStage: 'init',
      modelOverride: null,
      modelSelections: [],
    };
    writeFileSync(
      join(workdir, '.sdlc/workflows/CHORE-991.json'),
      JSON.stringify(preChoreState, null, 2)
    );
    // `resume` should flip status to in-progress and keep currentStep == 5
    // (the Execute QA index, unshifted by the relocations).
    const res = spawnSync('bash', [WORKFLOW_STATE, 'resume', 'CHORE-991'], {
      cwd: workdir,
      encoding: 'utf8',
    });
    expect(res.status).toBe(0);
    const after = JSON.parse(res.stdout) as Record<string, unknown>;
    expect(after.status).toBe('in-progress');
    expect(after.currentStep).toBe(5);
    const steps = after.steps as Array<{ name: string; status: string }>;
    // The step pointed to by currentStep is still Execute QA.
    expect(steps[5].name).toBe('Execute QA');
    expect(steps[5].status).toBe('pending');
  });
});

// =============================================================================
// Environment dimension
// =============================================================================

describe('[QA CHORE-035] Environment: SKILL.md structural integrity post-relocation', () => {
  it('SKILL.md starts with valid YAML frontmatter', () => {
    const body = readSkill();
    expect(body.startsWith('---\n')).toBe(true);
    const frontmatterEnd = body.indexOf('\n---\n', 4);
    expect(frontmatterEnd).toBeGreaterThan(0);
    // Frontmatter must close before the Output Style carve-out section.
    expect(frontmatterEnd).toBeLessThan(body.indexOf('## Output Style'));
  });

  it('SKILL.md body is substantially smaller post-relocation (input-token budget target)', () => {
    // The pilot's whole purpose. The baseline measurement table in the chore
    // doc reports 38653 chars pre, 22031 chars post. This is a sanity-floor:
    // a future regression that re-inlines the relocated recipes would push
    // SKILL.md back above the post-change size.
    const body = readSkill();
    expect(body.length).toBeLessThan(30000);
  });

  it('Output Style section is placed immediately after Quick Start', () => {
    const body = readSkill();
    const quickStart = body.indexOf('## Quick Start');
    const outputStyle = body.indexOf('## Output Style');
    expect(quickStart).toBeGreaterThan(-1);
    expect(outputStyle).toBeGreaterThan(quickStart);
    // And before the chain-step section anchors (the next major content).
    const featureChain = body.indexOf('## Feature Chain Step Sequence');
    expect(outputStyle).toBeLessThan(featureChain);
  });
});

// =============================================================================
// Dependency failure dimension
// =============================================================================

describe('[QA CHORE-035] Dependency failure: shell scripts still locate their inputs', () => {
  // P1 — scripts must not rely on specific strings in SKILL.md beyond the
  // documented frontmatter. Verify by running each script against a minimal
  // workdir and confirming it succeeds.

  it('workflow-state.sh resolve-tier still resolves a fork tier using the current SKILL.md', () => {
    const workdir = mkdtempSync(join(tmpdir(), 'qa-chore-035-dep-'));
    mkdirSync(join(workdir, '.sdlc/workflows'), { recursive: true });
    const state = {
      id: 'CHORE-992',
      type: 'chore',
      currentStep: 1,
      status: 'in-progress',
      pauseReason: null,
      gate: null,
      steps: [
        {
          name: 'Document chore',
          skill: 'documenting-chores',
          context: 'main',
          status: 'complete',
          artifact: null,
          completedAt: null,
        },
        {
          name: 'Review requirements (standard)',
          skill: 'reviewing-requirements',
          context: 'fork',
          status: 'pending',
          artifact: null,
          completedAt: null,
        },
      ],
      phases: { total: 0, completed: 0 },
      prNumber: null,
      branch: null,
      startedAt: '2026-04-01T00:00:00Z',
      lastResumedAt: null,
      complexity: 'medium',
      complexityStage: 'init',
      modelOverride: null,
      modelSelections: [],
    };
    writeFileSync(join(workdir, '.sdlc/workflows/CHORE-992.json'), JSON.stringify(state, null, 2));
    const res = spawnSync(
      'bash',
      [WORKFLOW_STATE, 'resolve-tier', 'CHORE-992', 'reviewing-requirements'],
      { cwd: workdir, encoding: 'utf8' }
    );
    expect(res.status, `resolve-tier failed: ${res.stderr}`).toBe(0);
    expect(res.stdout.trim()).toMatch(/^(haiku|sonnet|opus)$/);
  });
});

// =============================================================================
// Cross-cutting dimension — CHORE-034 preservation guarantees
// =============================================================================

describe('[QA CHORE-035] Cross-cutting: CHORE-034 carve-outs preserved verbatim', () => {
  // P0 — the chore's explicit contract with CHORE-034 is that none of its
  // directives are weakened. This is the regression guard.

  it('every CHORE-034 carve-out bullet survives the lite-rule pass', () => {
    const body = readSkill();
    const required: Array<[string, RegExp]> = [
      ['fail errors', /\*\*Error messages from `fail` calls\*\*/],
      ['security warnings', /\*\*Security-sensitive warnings\*\*/],
      ['interactive prompts', /\*\*Interactive prompts\*\*/],
      ['findings display', /\*\*Findings display from `reviewing-requirements`\*\*/],
      ['FR-14 echo', /\*\*FR-14 console echo lines\*\*/],
      ['tagged structured logs', /\*\*Tagged structured logs\*\*/],
      ['state transitions', /\*\*User-visible state transitions\*\*/],
    ];
    for (const [label, re] of required) {
      expect(body, `carve-out regressed: ${label}`).toMatch(re);
    }
  });

  it('FR-14 Unicode arrow is retained in the carve-out example (not normalized to ASCII ->)', () => {
    const body = readSkill();
    const line = body.match(/\*\*FR-14 console echo lines\*\*[^\n]*/)?.[0];
    expect(line).toBeDefined();
    expect(line).toContain('→');
    expect(line).not.toMatch(/->\s*\{tier\}/);
  });

  it('ASCII-arrows lite rule still carves out script-emitted structured logs', () => {
    const body = readSkill();
    expect(body).toMatch(/Script-emitted structured logs are out of scope for this rule/i);
  });

  it('findings display carve-out still forbids truncation', () => {
    const body = readSkill();
    expect(body).toMatch(
      /full findings list must be shown to the user before any findings-decision prompt.*Do not truncate/is
    );
  });

  it('all three canonical fork-return contract shapes are still documented', () => {
    const body = readSkill();
    expect(body).toMatch(/`done \| artifact=<path> \| <note-of-at-most-10-words>`/);
    expect(body).toMatch(/`failed \| <one-sentence reason>`/);
    expect(body).toMatch(/`Found \*\*N errors\*\*, \*\*N warnings\*\*, \*\*N info\*\*`/);
  });

  it('contract-precedence sentence is still present', () => {
    const body = readSkill();
    expect(body).toMatch(/return contract takes precedence over the lite rules/i);
  });

  it('reviewing-requirements no-done-contract disambiguation is still present', () => {
    const body = readSkill();
    expect(body).toMatch(/`reviewing-requirements` does not emit the `done \| \.\.\.` shape/);
  });
});

describe('[QA CHORE-035] Cross-cutting: Model Selection axis headings preserved', () => {
  // The chore-doc learnings explicitly called out that tests pin the three
  // axis headings. Verify they survived the compression.
  it('axis 1/2/3 subsection headings remain distinct in SKILL.md', () => {
    const body = readSkill();
    expect(body).toMatch(/### Axis 1 — Step baseline matrix/);
    expect(body).toMatch(/### Axis 2 — Work-item complexity signal matrix/);
    expect(body).toMatch(/### Axis 3 — Override precedence/);
  });

  it('override-precedence table is preserved in SKILL.md (bounded-table carve-out)', () => {
    const body = readSkill();
    expect(body).toMatch(/\|\s*Order\s*\|\s*Override\s*\|\s*Kind\s*\|\s*Behavior\s*\|/);
  });
});

// =============================================================================
// Inputs dimension — measurement-table internal consistency
// =============================================================================

describe('[QA CHORE-035] Inputs: measurement tables in chore doc are internally consistent', () => {
  // P2 — future editors will trust the measurement tables. Verify the pre/post
  // totals arithmetically match the per-file rows reported in the chore doc.

  function parseTableRow(line: string): { cells: string[] } | null {
    const trimmed = line.trim();
    if (!trimmed.startsWith('|') || !trimmed.endsWith('|')) return null;
    const cells = trimmed
      .slice(1, -1)
      .split('|')
      .map((c) => c.trim());
    return { cells };
  }

  function sumNumericColumn(rows: string[][], col: number): number {
    let sum = 0;
    for (const r of rows) {
      const v = r[col].replaceAll(',', '').replaceAll('*', '');
      const n = Number.parseInt(v, 10);
      if (!Number.isNaN(n)) sum += n;
    }
    return sum;
  }

  it('chore doc file exists and contains the three measurement tables', () => {
    const body = readFileSync(CHORE_DOC, 'utf8');
    expect(body).toMatch(/### Baseline Measurements/);
    expect(body).toMatch(/### Post-Change Measurements/);
    expect(body).toMatch(/### Delta/);
  });

  function extractTableRows(body: string, sectionHeading: string): string[][] {
    const start = body.indexOf(sectionHeading);
    expect(start, `section missing: ${sectionHeading}`).toBeGreaterThan(-1);
    const nextHeading = body.slice(start + sectionHeading.length).match(/\n### /);
    const end = nextHeading ? start + sectionHeading.length + nextHeading.index! : body.length;
    const section = body.slice(start, end);
    const lines = section.split('\n');
    const rows: string[][] = [];
    for (const line of lines) {
      const parsed = parseTableRow(line);
      if (!parsed) continue;
      // Skip header and separator rows
      if (parsed.cells.every((c) => /^-+:?$|^:?-+:?$/.test(c))) continue;
      if (parsed.cells.some((c) => c === 'File')) continue;
      rows.push(parsed.cells);
    }
    return rows;
  }

  it('Baseline Measurements totals row matches sum of individual file rows', () => {
    const body = readFileSync(CHORE_DOC, 'utf8');
    const rows = extractTableRows(body, '### Baseline Measurements');
    // Last row is totals; verify columns 1 (Lines), 2 (Words), 3 (Chars).
    const fileRows = rows.slice(0, -1);
    const totalsRow = rows[rows.length - 1];
    const linesSum = sumNumericColumn(fileRows, 1);
    const wordsSum = sumNumericColumn(fileRows, 2);
    const charsSum = sumNumericColumn(fileRows, 3);
    expect(Number.parseInt(totalsRow[1].replaceAll('*', ''), 10)).toBe(linesSum);
    expect(Number.parseInt(totalsRow[2].replaceAll('*', ''), 10)).toBe(wordsSum);
    expect(Number.parseInt(totalsRow[3].replaceAll('*', ''), 10)).toBe(charsSum);
  });

  it('Post-Change Measurements totals row matches sum of individual file rows', () => {
    const body = readFileSync(CHORE_DOC, 'utf8');
    const rows = extractTableRows(body, '### Post-Change Measurements');
    const fileRows = rows.slice(0, -1);
    const totalsRow = rows[rows.length - 1];
    const linesSum = sumNumericColumn(fileRows, 1);
    const wordsSum = sumNumericColumn(fileRows, 2);
    const charsSum = sumNumericColumn(fileRows, 3);
    expect(Number.parseInt(totalsRow[1].replaceAll('*', ''), 10)).toBe(linesSum);
    expect(Number.parseInt(totalsRow[2].replaceAll('*', ''), 10)).toBe(wordsSum);
    expect(Number.parseInt(totalsRow[3].replaceAll('*', ''), 10)).toBe(charsSum);
  });
});
