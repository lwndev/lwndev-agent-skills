import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const DOCUMENTING_QA_LOADER = join(
  process.cwd(),
  'plugins/lwndev-sdlc/skills/documenting-qa/scripts/persona-loader.sh'
);
const EXECUTING_QA_LOADER = join(
  process.cwd(),
  'plugins/lwndev-sdlc/skills/executing-qa/scripts/persona-loader.sh'
);
const DOCUMENTING_QA_SKILL_DIR = join(process.cwd(), 'plugins/lwndev-sdlc/skills/documenting-qa');
const EXECUTING_QA_SKILL_DIR = join(process.cwd(), 'plugins/lwndev-sdlc/skills/executing-qa');

type RunResult = {
  stdout: string;
  stderr: string;
  status: number;
};

// Source the persona-loader.sh helper in a clean bash subshell, invoke
// `load_persona <name> <skill_dir>`, and capture stdout/stderr/status.
function runLoader(loader: string, personaName: string, skillDir: string): RunResult {
  const script = `source "${loader}" && load_persona "${personaName}" "${skillDir}"`;
  const result = spawnSync('bash', ['-c', script], {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  return {
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    status: result.status ?? -1,
  };
}

let fixture: string;

beforeEach(() => {
  fixture = mkdtempSync(join(tmpdir(), 'persona-loader-'));
});

afterEach(() => {
  rmSync(fixture, { recursive: true, force: true });
});

describe('persona-loader.sh', () => {
  describe('real qa persona (shipped in documenting-qa)', () => {
    it('loads successfully and emits all five dimension headings', () => {
      const result = runLoader(DOCUMENTING_QA_LOADER, 'qa', DOCUMENTING_QA_SKILL_DIR);

      expect(result.status).toBe(0);
      expect(result.stderr).toBe('');
      expect(result.stdout).toContain('### Inputs');
      expect(result.stdout).toContain('### State transitions');
      expect(result.stdout).toContain('### Environment');
      expect(result.stdout).toContain('### Dependency failure');
      expect(result.stdout).toContain('### Cross-cutting');
    });

    it('includes the "empty findings is suspicious" directive (FR-6/FR-8)', () => {
      const result = runLoader(DOCUMENTING_QA_LOADER, 'qa', DOCUMENTING_QA_SKILL_DIR);

      expect(result.status).toBe(0);
      // Case-insensitive check for the core phrase.
      expect(result.stdout.toLowerCase()).toContain('empty findings');
      expect(result.stdout.toLowerCase()).toMatch(/empty[- ]findings|empty findings is suspicious/);
    });
  });

  describe('real qa persona (shipped in executing-qa)', () => {
    it('loads successfully and emits all five dimension headings', () => {
      const result = runLoader(EXECUTING_QA_LOADER, 'qa', EXECUTING_QA_SKILL_DIR);

      expect(result.status).toBe(0);
      expect(result.stderr).toBe('');
      expect(result.stdout).toContain('### Inputs');
      expect(result.stdout).toContain('### State transitions');
      expect(result.stdout).toContain('### Environment');
      expect(result.stdout).toContain('### Dependency failure');
      expect(result.stdout).toContain('### Cross-cutting');
    });
  });

  describe('missing persona — edge case 8', () => {
    it('returns non-zero and emits a clear error referencing the expected path', () => {
      mkdirSync(join(fixture, 'personas'), { recursive: true });

      const result = runLoader(DOCUMENTING_QA_LOADER, 'nonexistent', fixture);

      expect(result.status).not.toBe(0);
      expect(result.stdout).toBe('');
      expect(result.stderr).toContain('persona-loader: error:');
      expect(result.stderr).toContain('persona file not found');
      expect(result.stderr).toContain(join(fixture, 'personas', 'nonexistent.md'));
    });

    it('lists available personas in the error message when the directory is populated', () => {
      mkdirSync(join(fixture, 'personas'), { recursive: true });
      writeFileSync(join(fixture, 'personas', 'a11y.md'), '---\nname: a11y\n---\nbody\n');

      const result = runLoader(DOCUMENTING_QA_LOADER, 'missing', fixture);

      expect(result.status).not.toBe(0);
      expect(result.stderr).toContain('Available personas:');
      expect(result.stderr).toContain('a11y.md');
    });
  });

  describe('malformed frontmatter', () => {
    it('returns non-zero when the opening --- delimiter is missing', () => {
      mkdirSync(join(fixture, 'personas'), { recursive: true });
      writeFileSync(
        join(fixture, 'personas', 'broken.md'),
        'no frontmatter at all\nname: broken\ndescription: x\n'
      );

      const result = runLoader(DOCUMENTING_QA_LOADER, 'broken', fixture);

      expect(result.status).not.toBe(0);
      expect(result.stdout).toBe('');
      expect(result.stderr).toContain('persona-loader: error:');
      expect(result.stderr).toContain('frontmatter');
    });

    it('returns non-zero when the closing --- delimiter is missing', () => {
      mkdirSync(join(fixture, 'personas'), { recursive: true });
      writeFileSync(
        join(fixture, 'personas', 'unclosed.md'),
        '---\nname: unclosed\ndescription: x\nbody text without closing delimiter\n'
      );

      const result = runLoader(DOCUMENTING_QA_LOADER, 'unclosed', fixture);

      expect(result.status).not.toBe(0);
      expect(result.stderr).toContain('persona-loader: error:');
      expect(result.stderr).toContain('frontmatter');
    });

    it('returns non-zero when the name field is missing', () => {
      mkdirSync(join(fixture, 'personas'), { recursive: true });
      writeFileSync(
        join(fixture, 'personas', 'noname.md'),
        '---\ndescription: has no name field\n---\nbody\n'
      );

      const result = runLoader(DOCUMENTING_QA_LOADER, 'noname', fixture);

      expect(result.status).not.toBe(0);
      expect(result.stderr).toContain('persona-loader: error:');
      expect(result.stderr).toContain('name:');
    });

    it('returns non-zero when the name field is empty', () => {
      mkdirSync(join(fixture, 'personas'), { recursive: true });
      writeFileSync(
        join(fixture, 'personas', 'emptyname.md'),
        '---\nname:\ndescription: blank name\n---\nbody\n'
      );

      const result = runLoader(DOCUMENTING_QA_LOADER, 'emptyname', fixture);

      expect(result.status).not.toBe(0);
      expect(result.stderr).toContain('persona-loader: error:');
    });
  });

  describe('extensibility — FR-7 (drop-in new persona)', () => {
    it('loads a newly-added persona `fake-test-persona` from a scratch fixture with no loader changes', () => {
      mkdirSync(join(fixture, 'personas'), { recursive: true });
      const personaBody = [
        '---',
        'name: fake-test-persona',
        'description: Synthetic persona used to prove FR-7 drop-in extensibility.',
        'version: 1',
        '---',
        '',
        '# Fake Test Persona',
        '',
        'This persona proves the loader resolves any `personas/{name}.md` file',
        'without requiring source changes.',
        '',
      ].join('\n');
      writeFileSync(join(fixture, 'personas', 'fake-test-persona.md'), personaBody);

      const result = runLoader(DOCUMENTING_QA_LOADER, 'fake-test-persona', fixture);

      expect(result.status).toBe(0);
      expect(result.stderr).toBe('');
      expect(result.stdout).toContain('name: fake-test-persona');
      expect(result.stdout).toContain('# Fake Test Persona');
      expect(result.stdout).toContain('FR-7 drop-in extensibility');
    });

    it('loads the same new persona equally through the executing-qa loader (both loaders identical)', () => {
      mkdirSync(join(fixture, 'personas'), { recursive: true });
      const personaBody = [
        '---',
        'name: another-persona',
        'description: Second synthetic persona.',
        '---',
        '',
        '# Another Persona',
        '',
      ].join('\n');
      writeFileSync(join(fixture, 'personas', 'another-persona.md'), personaBody);

      const docResult = runLoader(DOCUMENTING_QA_LOADER, 'another-persona', fixture);
      const execResult = runLoader(EXECUTING_QA_LOADER, 'another-persona', fixture);

      expect(docResult.status).toBe(0);
      expect(execResult.status).toBe(0);
      expect(docResult.stdout).toBe(execResult.stdout);
    });
  });

  describe('argument validation', () => {
    it('returns non-zero when called with no arguments', () => {
      const result = spawnSync(
        'bash',
        ['-c', `source "${DOCUMENTING_QA_LOADER}" && load_persona`],
        { encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'] }
      );

      expect(result.status).not.toBe(0);
      expect(result.stderr ?? '').toContain('persona-loader: error:');
    });
  });
});
