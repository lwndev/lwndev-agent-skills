import { truncate } from '../lib/prompts.js';

describe('prompts utilities', () => {
  describe('truncate', () => {
    it('should not truncate strings shorter than maxLength', () => {
      expect(truncate('hello', 10)).toBe('hello');
    });

    it('should not truncate strings equal to maxLength', () => {
      expect(truncate('hello', 5)).toBe('hello');
    });

    it('should truncate strings longer than maxLength with ellipsis', () => {
      expect(truncate('hello world', 8)).toBe('hello...');
    });

    it('should handle empty strings', () => {
      expect(truncate('', 10)).toBe('');
    });

    it('should handle very short maxLength', () => {
      expect(truncate('hello', 4)).toBe('h...');
    });
  });
});
