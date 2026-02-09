import { execSync } from 'node:child_process';
import { access, rm, readFile } from 'node:fs/promises';
import { join } from 'node:path';

const TEST_SKILL_NAME = 'test-scaffold-skill';
const TEST_SKILL_PATH = join('src/skills', TEST_SKILL_NAME);

const TEMPLATE_SKILL_NAME = 'test-scaffold-template';
const TEMPLATE_SKILL_PATH = join('src/skills', TEMPLATE_SKILL_NAME);

describe('scaffold script integration', () => {
  afterAll(async () => {
    // Clean up test skill if it exists
    try {
      await rm(TEST_SKILL_PATH, { recursive: true, force: true });
    } catch {
      // Ignore if doesn't exist
    }
  });

  it('should create a new skill with asm scaffold', async () => {
    // Run asm scaffold directly (the script is interactive, so we test the underlying command)
    const command = `asm scaffold ${TEST_SKILL_NAME} -d "A test skill created by automated tests" -o src/skills -f`;

    execSync(command, { stdio: 'pipe' });

    // Verify skill was created
    await expect(access(TEST_SKILL_PATH)).resolves.toBeUndefined();
    await expect(access(join(TEST_SKILL_PATH, 'SKILL.md'))).resolves.toBeUndefined();
  });

  it('should create SKILL.md with correct frontmatter', async () => {
    const skillMdPath = join(TEST_SKILL_PATH, 'SKILL.md');
    const content = await readFile(skillMdPath, 'utf-8');

    // Check frontmatter
    expect(content).toContain('---');
    expect(content).toContain(`name: ${TEST_SKILL_NAME}`);
    expect(content).toContain('description:');
  });

  it('should be discoverable by getSourceSkills after creation', async () => {
    const { getSourceSkills } = await import('../lib/skill-utils.js');
    const skills = await getSourceSkills();
    const testSkill = skills.find((s) => s.name === TEST_SKILL_NAME);

    expect(testSkill).toBeDefined();
    expect(testSkill?.description).toContain('test skill');
  });
});

describe('scaffold template options', () => {
  beforeEach(async () => {
    // Clean slate for each test to avoid order-dependent results
    try {
      await rm(TEMPLATE_SKILL_PATH, { recursive: true, force: true });
    } catch {
      // Ignore if doesn't exist
    }
  });

  afterAll(async () => {
    try {
      await rm(TEMPLATE_SKILL_PATH, { recursive: true, force: true });
    } catch {
      // Ignore if doesn't exist
    }
  });

  it('should pass template type to scaffold API', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Template test" -o src/skills -f --template agent`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(TEMPLATE_SKILL_PATH, 'SKILL.md'), 'utf-8');
    expect(content).toContain(`name: ${TEMPLATE_SKILL_NAME}`);
    // Agent template sets the agent field
    expect(content).toContain('agent:');
  });

  it('should pass minimal flag to scaffold API', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Minimal test" -o src/skills -f --minimal`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(TEMPLATE_SKILL_PATH, 'SKILL.md'), 'utf-8');
    expect(content).toContain(`name: ${TEMPLATE_SKILL_NAME}`);
    // Minimal templates are shorter — no extended guidance sections
    expect(content.length).toBeLessThan(2000);
  });

  it('should pass memory scope to scaffold API', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Memory test" -o src/skills -f --memory user`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(TEMPLATE_SKILL_PATH, 'SKILL.md'), 'utf-8');
    expect(content).toContain('memory:');
    expect(content).toContain('user');
  });

  it('should pass model to scaffold API for agent template', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Model test" -o src/skills -f --template agent --model haiku`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(TEMPLATE_SKILL_PATH, 'SKILL.md'), 'utf-8');
    expect(content).toContain('model:');
    expect(content).toContain('haiku');
  });

  it('should pass argument hint to scaffold API', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Hint test" -o src/skills -f --argument-hint "<query> [--deep]"`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(TEMPLATE_SKILL_PATH, 'SKILL.md'), 'utf-8');
    expect(content).toContain('argument-hint:');
  });

  it('should combine multiple template options', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Combined test" -o src/skills -f --template agent --minimal --memory project --model opus --argument-hint "<file>"`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(TEMPLATE_SKILL_PATH, 'SKILL.md'), 'utf-8');
    expect(content).toContain(`name: ${TEMPLATE_SKILL_NAME}`);
    expect(content).toContain('memory:');
    expect(content).toContain('model:');
    expect(content).toContain('argument-hint:');
    // Minimal agent template is concise
    expect(content.length).toBeLessThan(2000);
  });
});
