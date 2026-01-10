import { execSync } from 'node:child_process';
import { access, rm, readFile } from 'node:fs/promises';
import { join } from 'node:path';

const TEST_SKILL_NAME = 'test-scaffold-skill';
const TEST_SKILL_PATH = join('src/skills', TEST_SKILL_NAME);

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
