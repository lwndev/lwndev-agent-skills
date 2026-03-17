# Bug Categories Reference

This document provides detailed guidance for each bug category, including common use cases, typical affected files, and suggested acceptance criteria.

## Table of Contents

- [Runtime Error](#runtime-error)
- [Logic Error](#logic-error)
- [UI Defect](#ui-defect)
- [Performance](#performance)
- [Security](#security)
- [Regression](#regression)

---

## Runtime Error

Crashes, unhandled exceptions, and fatal errors that prevent normal operation.

### Common Use Cases

- Unhandled promise rejections or uncaught exceptions
- Null/undefined reference errors
- Stack overflow from infinite recursion
- Out-of-memory crashes
- Missing required environment variables at startup
- Failed assertions or invariant violations

### Typical Affected Files

- Source files where the error originates
- Error handling middleware or global handlers
- Configuration/initialization files
- Dependency entry points (if caused by a library)

### Suggested Acceptance Criteria

- [ ] The crash no longer occurs under the reported conditions
- [ ] Error is handled gracefully with an appropriate message
- [ ] Unit tests cover the previously crashing code path
- [ ] No new unhandled exceptions introduced
- [ ] Application recovers or exits cleanly

### Notes

- Include the full stack trace in the bug document when available
- Check if the error is environment-specific (e.g., Node version, OS)
- Consider adding error boundaries or global error handlers if missing

---

## Logic Error

Incorrect behavior, wrong calculations, or bad state management.

### Common Use Cases

- Functions returning wrong results
- Incorrect conditional logic (off-by-one, wrong operator)
- State not updated correctly after an action
- Data transformations producing incorrect output
- Race conditions causing inconsistent state
- Incorrect sorting, filtering, or grouping

### Typical Affected Files

- Source files containing the flawed logic
- Related utility or helper functions
- State management files (stores, reducers, context)
- Test files that missed the edge case

### Suggested Acceptance Criteria

- [ ] Function produces correct results for the reported case
- [ ] Edge cases are covered by new or updated tests
- [ ] Related logic paths verified for similar issues
- [ ] State transitions are correct and consistent
- [ ] No regressions in adjacent functionality

### Notes

- Logic errors can be subtle — test with boundary values and edge cases
- Trace the data flow end-to-end to understand the full impact
- Consider whether the logic error exists in similar code elsewhere

---

## UI Defect

Visual glitches, layout issues, and rendering problems.

### Common Use Cases

- Elements overlapping or misaligned
- Incorrect colors, fonts, or spacing
- Responsive layout broken at certain breakpoints
- Components not rendering or rendering incorrectly
- Animation or transition glitches
- Accessibility issues (missing labels, poor contrast)

### Typical Affected Files

- Component files (`.tsx`, `.jsx`, `.vue`)
- Stylesheet files (`.css`, `.scss`, `.module.css`)
- Layout or container components
- Theme or design token files
- Responsive utility files

### Suggested Acceptance Criteria

- [ ] Visual defect is corrected at the reported viewport/resolution
- [ ] Layout is consistent across supported browsers
- [ ] Responsive behavior works at standard breakpoints
- [ ] No visual regressions in adjacent components
- [ ] Accessibility standards maintained (WCAG compliance)

### Notes

- Include screenshots or recordings in the bug document when possible
- Test across multiple browsers and viewport sizes
- Check if the defect is caused by CSS specificity conflicts

---

## Performance

Slowness, memory leaks, and resource exhaustion.

### Common Use Cases

- Slow API responses or page load times
- Memory leaks causing gradual degradation
- Excessive CPU usage during specific operations
- Unnecessary re-renders in UI frameworks
- Large bundle sizes impacting load time
- Database queries without proper indexing

### Typical Affected Files

- Source files containing the slow operation
- Database query files or ORM models
- API route handlers or middleware
- Component files with rendering inefficiencies
- Configuration files (caching, connection pools)
- Build configuration (bundle splitting, tree shaking)

### Suggested Acceptance Criteria

- [ ] Operation completes within acceptable time threshold
- [ ] Memory usage remains stable over extended use
- [ ] No resource leaks detected (connections, file handles, listeners)
- [ ] Performance improvement is measurable and documented
- [ ] No functional regressions from optimization

### Notes

- Include before/after metrics when documenting the fix
- Use profiling tools to identify the actual bottleneck before fixing
- Consider whether the fix trades off readability for performance

---

## Security

Vulnerabilities, authentication bypasses, and data exposure.

### Common Use Cases

- Authentication or authorization bypasses
- SQL injection, XSS, or command injection vulnerabilities
- Sensitive data exposed in logs, responses, or URLs
- Insecure dependencies with known CVEs
- Missing input validation or sanitization
- Improper session management or token handling

### Typical Affected Files

- Authentication/authorization middleware
- Input validation and sanitization logic
- API route handlers processing user input
- Configuration files with secrets or credentials
- Dependency files (`package.json`, `package-lock.json`)
- Logging and error reporting modules

### Suggested Acceptance Criteria

- [ ] Vulnerability is no longer exploitable
- [ ] Input validation covers the attack vector
- [ ] Sensitive data is not exposed in any output
- [ ] Security tests cover the previously vulnerable path
- [ ] Dependencies updated to patched versions (if applicable)
- [ ] No new vulnerabilities introduced

### Notes

- Treat security bugs with urgency — assess severity carefully
- Do not include exploit details in public issue trackers
- Consider a broader audit of similar patterns in the codebase
- Follow responsible disclosure practices if the vulnerability affects users

---

## Regression

Previously working functionality that broke due to recent changes.

### Common Use Cases

- Feature that worked before a recent deploy or merge
- Test that previously passed now failing
- Behavior change caused by a dependency update
- Side effect from a refactoring or optimization
- Configuration change that broke existing functionality
- API contract change that broke consumers

### Typical Affected Files

- Files modified in the commit or PR that introduced the regression
- Test files that should have caught the regression
- Integration points between affected and changed components
- Configuration files if settings were altered

### Suggested Acceptance Criteria

- [ ] Previously working functionality is restored
- [ ] Regression test added to prevent recurrence
- [ ] Root cause in the introducing change is identified and documented
- [ ] No other regressions from the fix
- [ ] Related test coverage improved

### Notes

- Use `git bisect` to identify the exact commit that introduced the regression
- Review the PR or commit that caused the regression for other potential issues
- Consider whether the original change needs to be reverted or patched
- Add the regression test to CI to prevent future recurrence
