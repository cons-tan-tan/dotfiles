---
name: create-pr
description: Runs the full PR workflow — creates a feature branch, commits, pushes, and opens the pull request. Use when the user asks to create or open a PR ("create a PR", "push this up and open a PR").
---

# Create PR

## PR Granularity

A PR is a reviewable responsibility unit; one PR may contain multiple atomic commits. A branch is not a PR boundary: split independent work into separate PRs and stack only dependent work.

## Workflow

1. Inspect the current branch, status, diff, target repository, and push remote. Check for an open PR matching the target repository and head repository/branch.

2. Use the repository's default branch as the base unless the user, the matching PR, or the stack specifies another target. Create a feature branch when working on the default branch; otherwise reuse a suitable branch. Follow repository branch naming conventions.

3. Review local changes (staged, unstaged, and untracked) and the complete PR diff against the intended base. Exclude unrelated changes, temporary files, secrets, generated junk, and debug-only edits.

4. Commit any remaining changes with the available `commit` skill. Validate as needed for the change and repository requirements, reusing results that still apply.

5. Prepare a PR title and body proportional to the change:

   - Follow user and repository requirements, including the PR template. Otherwise, match the language and title style of representative recent PRs.
   - For a small focused change, briefly explain what changed and why. When structure helps, consider Summary, What Changed, Why, Testing, Related Issues; combine, rename, or omit sections as appropriate.
   - Include relevant validation results and any unverified behavior that matters to the review.
   - Use `--body-file` (file or stdin) for multiline bodies. Do not encode line breaks as literal `\n` sequences in `--body`.

6. When visual evidence helps explain the change, attach real local screenshots or short videos with `gh pr create --attach`. Skip when there is nothing useful to show or the command's help does not list `--attach`. Prefer Markdown references to local paths in the body so alt text survives upload. Add media later with `gh pr edit` or `gh pr comment` instead of recreating the PR. See `gh pr create --help` and [the attachment documentation](https://gh.io/gh-attach).

7. Publish using the path that matches the PR structure:

   - Use `gh-stack` only when requested or when the branch is already stacked; follow its skill for branch relationships and publication. Adjust generated titles and bodies to match step 5, preserving stack footers.
   - For an ordinary PR, push to the selected remote and create the PR with the prepared title and body, or update the matching open PR. Confirm the base and head match the reviewed diff.

8. Report the PR URL and current validation status. If publishing fails, inspect the error and remote state before retrying only the unfinished operation. A partial attachment failure can leave a successfully created PR.
