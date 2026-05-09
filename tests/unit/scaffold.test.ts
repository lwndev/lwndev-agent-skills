import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';
import { execSync } from 'node:child_process';
import { access, rm, readFile, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const TEST_SKILL_NAME = 'test-scaffold-skill';
const TEMPLATE_SKILL_NAME = 'test-scaffold-template';

describe('scaffold script integration', () => {
  let tmpDir: string;
  let testSkillPath: string;

  beforeAll(async () => {
    tmpDir = await mkdtemp(join(tmpdir(), 'scaffold-integration-'));
    testSkillPath = join(tmpDir, TEST_SKILL_NAME);
  });

  afterAll(async () => {
    await rm(tmpDir, { recursive: true, force: true });
  });

  it('should create a new skill with asm scaffold', async () => {
    const command = `asm scaffold ${TEST_SKILL_NAME} -d "A test skill created by automated tests" -o ${tmpDir} -f`;

    execSync(command, { stdio: 'pipe' });

    // Verify skill was created
    await expect(access(testSkillPath)).resolves.toBeUndefined();
    await expect(access(join(testSkillPath, 'SKILL.md'))).resolves.toBeUndefined();
  });

  it('should create SKILL.md with correct frontmatter', async () => {
    const skillMdPath = join(testSkillPath, 'SKILL.md');
    const content = await readFile(skillMdPath, 'utf-8');

    // Check frontmatter
    expect(content).toContain('---');
    expect(content).toContain(`name: ${TEST_SKILL_NAME}`);
    expect(content).toContain('description:');
  });

  it('should be discoverable by skill-discovery logic after creation', async () => {
    const { getSkillsFromDir } = await import('../../scripts/lib/skill-utils.js');
    const skills = await getSkillsFromDir(tmpDir);
    const scaffolded = skills.find((s) => s.name === TEST_SKILL_NAME);
    expect(scaffolded).toBeDefined();
    expect(scaffolded?.description).toBe('A test skill created by automated tests');
  });
});

describe('scaffold template options', () => {
  let tmpDir: string;
  let templateSkillPath: string;

  beforeAll(async () => {
    tmpDir = await mkdtemp(join(tmpdir(), 'scaffold-template-'));
    templateSkillPath = join(tmpDir, TEMPLATE_SKILL_NAME);
  });

  beforeEach(async () => {
    // Clean slate for each test to avoid order-dependent results
    try {
      await rm(templateSkillPath, { recursive: true, force: true });
    } catch {
      // Ignore if doesn't exist
    }
  });

  afterAll(async () => {
    await rm(tmpDir, { recursive: true, force: true });
  });

  it('should pass template type to scaffold API', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Template test" -o ${tmpDir} -f --template forked`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(templateSkillPath, 'SKILL.md'), 'utf-8');
    expect(content).toContain(`name: ${TEMPLATE_SKILL_NAME}`);
    // Forked template sets the context field
    expect(content).toContain('context:');
  });

  it('should pass minimal flag to scaffold API', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Minimal test" -o ${tmpDir} -f --minimal`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(templateSkillPath, 'SKILL.md'), 'utf-8');
    expect(content).toContain(`name: ${TEMPLATE_SKILL_NAME}`);
    // Minimal templates are shorter — no extended guidance sections
    expect(content.length).toBeLessThan(2000);
  });

  it('should pass agent name to scaffold API', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Agent test" -o ${tmpDir} -f --agent Explore`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(templateSkillPath, 'SKILL.md'), 'utf-8');
    expect(content).toContain('agent:');
    expect(content).toContain('Explore');
  });

  it('should pass license to scaffold API', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "License test" -o ${tmpDir} -f --license MIT`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(templateSkillPath, 'SKILL.md'), 'utf-8');
    expect(content).toContain('license:');
    expect(content).toContain('MIT');
  });

  it('should pass argument hint to scaffold API', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Hint test" -o ${tmpDir} -f --argument-hint "<query> [--deep]"`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(templateSkillPath, 'SKILL.md'), 'utf-8');
    expect(content).toContain('argument-hint:');
  });

  it('should combine multiple template options', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Combined test" -o ${tmpDir} -f --template forked --minimal --agent Explore --argument-hint "<file>" --license MIT`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(templateSkillPath, 'SKILL.md'), 'utf-8');
    expect(content).toContain(`name: ${TEMPLATE_SKILL_NAME}`);
    expect(content).toContain('context:');
    expect(content).toContain('agent:');
    expect(content).toContain('argument-hint:');
    // Minimal forked template is concise
    expect(content.length).toBeLessThan(2000);
  });
});
