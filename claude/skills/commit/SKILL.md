---
name: commit
description: Creates atomic, revertable git commits following Conventional Commits. Splits changes into logical units by hunk. Use when committing code (e.g., "commit this" or "done, let's commit").
---

You are an expert git commit architect creating fine-grained, independently revertable commits following Conventional Commits specification.

- Current status: !`git status --short`
- Changes: !`git diff HEAD`
- Recent commits: !`git log --oneline -20`

## Core Philosophy

**Revertability First**: Each commit must be revertable independently without breaking other functionality. Prefer smaller, granular commits over large groupings. Split by hunks within files, not just entire files.

## Workflow

1. **Analyse the changes above**: Review the git state already provided. Summarize what changed before asking any splitting questions.
2. **Review history**: Match existing Conventional Commits patterns (structure, scope naming, message style) from the log above. Ignore non-Conventional Commit styles.
3. **Identify revertable units**: Examine each hunk separately - can it be reverted independently?
4. **Propose split plan**: Recommend a commit split and explain it before proceeding. When confirmation is required, use the question tool to ask the user.

5. **Create safety backup** (only when splitting hunks within a file):
   If a single file needs to be split into multiple commits:
   ```bash
   cp "$file" "${file}.local.bak"
   ```
   Example: `path/to/file.ext` → `path/to/file.ext.local.bak`

   Skip this step if each file goes into its own commit.

6. **For each commit unit**:
   - If splitting hunks: Reset file with `git checkout -- <file>`, then reference the backup
   - Use **Edit tool** to apply only the changes for this unit
   - Stage: `git add <file>`
   - Craft message following format below
   - Commit and verify with `git show HEAD`
   - Repeat until all changes are committed

7. **Verify**: Confirm the committed result matches the original changes:
   ```bash
   diff "$file" "${file}.local.bak"
   ```
   If there is any difference, restore from backup and redo the split.

8. **Cleanup**: Remove the `*.local.bak` files created in step 6:
   ```bash
   rm "path/to/file.ext.local.bak"
   ```

**NEVER use `git add -p` or `git add --interactive`** - Claude Code cannot handle interactive commands.

## Recovery

If something goes wrong when splitting hunks within a file:

```bash
# Restore the complete modified file from backup
cp "path/to/file.ext.local.bak" "path/to/file.ext"
```

Keep `*.local.bak` files until all commits from that file are complete.

## Commit Message Format

```
<type>: <subject>

[<body>]
```

**Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`

**Scope**: Optional. Only use scope when matching existing commit patterns in the project or when explicitly specified. By default, omit scope (e.g., prefer `feat: add login` over `feat(auth): add login`).

**Body**: May be omitted only when the change is minor enough that type and subject are completely self-explanatory. When included, body should explain:
- WHAT changed and WHY
- Problem context and solution rationale
- Implementation decisions
- Potential impacts
- Wrap at 72 characters

## Quality Checks

- Can this be reverted without breaking other functionality?
- Is this the smallest logical unit?
- Does message clearly explain the change?
- Does it match project's Conventional Commits patterns (if any)?
- No debugging statements or commented code without explanation

## Example

```
feat: add RefreshTokenService class
```

```
feat: integrate token rotation in middleware
```

```
fix: prevent race condition in token refresh

Multiple concurrent requests could trigger simultaneous token
refreshes, causing invalid token errors. Added mutex lock to
ensure only one refresh occurs at a time.
```

## Key Principles

- Always use **English** for commit messages
- **Never push to main branch directly** - create a PR instead
- When in doubt, prefer smaller commits (can squash later, can't easily split)
- Match project's scope naming and conventions only when Conventional Commits are found
- Each commit must pass: "If I revert this, will it break other features?"
- If the commit is just for applying formatter, use `chore: format`
