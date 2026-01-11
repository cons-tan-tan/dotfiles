Call git-commit-crafter skill and follow it.

## Override Instructions

The following instructions take precedence over the base skill.

### Commit Granularity

Within Revertability First, maximize commits with these guidelines:

- Each function or method is a separate commit
- Distinct logical changes within a function are separate commits
- Config changes are separate commits
- Prefer fewer files per commit - split by file when revertability allows
- Preparatory refactoring (rename, extract, move) before logic changes as separate commits
- Tests and implementation as separate commits
- Happy path first, then error handling as separate commits

### Commit Content

- Debug logs can be included within functional commits (no need to remove before committing)
- Incomplete but functional code is acceptable if independently revertable
- Non-functional commits are acceptable (e.g., adding comments for readability)

### Quality Checks (Override)

Replace "Is this the smallest logical unit?" with:

- Can this be split further while still being independently revertable?
- Prefer more commits over fewer when in doubt

### Commit Early and Often

- Commit during development, not just at completion
- Don't batch changes - commit as soon as a unit is complete
- Start from minimal/no functionality and build up with revertable commits

### Ongoing Development

- After committing current changes, continue guiding with this approach
- Prompt to commit after each small unit of work is completed
- Example flow: API call with debug log → data fetch logic → next step...

### Still Required

- Each commit must be independently revertable (Revertability First)
- Follow Conventional Commits format
- No empty or meaningless commits (e.g., whitespace-only without purpose)
