import { execSync } from 'node:child_process';
import { access, rm, readFile } from 'node:fs/promises';
import { join } from 'node:path';

const PLUGIN_SKILLS_DIR = 'plugins/lwndev-sdlc/skills';
const TEST_SKILL_NAME = 'test-scaffold-skill';
const TEST_SKILL_PATH = join(PLUGIN_SKILLS_DIR, TEST_SKILL_NAME);

const TEMPLATE_SKILL_NAME = 'test-scaffold-template';
const TEMPLATE_SKILL_PATH = join(PLUGIN_SKILLS_DIR, TEMPLATE_SKILL_NAME);

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
    const command = `asm scaffold ${TEST_SKILL_NAME} -d "A test skill created by automated tests" -o ${PLUGIN_SKILLS_DIR} -f`;

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
    const skills = await getSourceSkills('lwndev-sdlc');
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
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Template test" -o ${PLUGIN_SKILLS_DIR} -f --template forked`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(TEMPLATE_SKILL_PATH, 'SKILL.md'), 'utf-8');
    expect(content).toContain(`name: ${TEMPLATE_SKILL_NAME}`);
    // Forked template sets the context field
    expect(content).toContain('context:');
  });

  it('should pass minimal flag to scaffold API', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Minimal test" -o ${PLUGIN_SKILLS_DIR} -f --minimal`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(TEMPLATE_SKILL_PATH, 'SKILL.md'), 'utf-8');
    expect(content).toContain(`name: ${TEMPLATE_SKILL_NAME}`);
    // Minimal templates are shorter — no extended guidance sections
    expect(content.length).toBeLessThan(2000);
  });

  it('should pass agent name to scaffold API', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Agent test" -o ${PLUGIN_SKILLS_DIR} -f --agent Explore`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(TEMPLATE_SKILL_PATH, 'SKILL.md'), 'utf-8');
    expect(content).toContain('agent:');
    expect(content).toContain('Explore');
  });

  it('should pass license to scaffold API', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "License test" -o ${PLUGIN_SKILLS_DIR} -f --license MIT`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(TEMPLATE_SKILL_PATH, 'SKILL.md'), 'utf-8');
    expect(content).toContain('license:');
    expect(content).toContain('MIT');
  });

  it('should pass argument hint to scaffold API', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Hint test" -o ${PLUGIN_SKILLS_DIR} -f --argument-hint "<query> [--deep]"`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(TEMPLATE_SKILL_PATH, 'SKILL.md'), 'utf-8');
    expect(content).toContain('argument-hint:');
  });

  it('should combine multiple template options', async () => {
    const command = `asm scaffold ${TEMPLATE_SKILL_NAME} -d "Combined test" -o ${PLUGIN_SKILLS_DIR} -f --template forked --minimal --agent Explore --argument-hint "<file>" --license MIT`;

    execSync(command, { stdio: 'pipe' });

    const content = await readFile(join(TEMPLATE_SKILL_PATH, 'SKILL.md'), 'utf-8');
    expect(content).toContain(`name: ${TEMPLATE_SKILL_NAME}`);
    expect(content).toContain('context:');
    expect(content).toContain('agent:');
    expect(content).toContain('argument-hint:');
    // Minimal forked template is concise
    expect(content.length).toBeLessThan(2000);
  });
});
