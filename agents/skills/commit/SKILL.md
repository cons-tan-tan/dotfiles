---
name: commit
description: Creates atomic Conventional Commits. Use when committing code changes, splitting hunks into revertible units, or writing commit messages.
---

# Commit

Create small, independently revertible Conventional Commits.

## Arguments

`push`: whether to push after committing (default: `false`).

## Workflow

1. Inspect the current branch, staged and unstaged changes, and relevant untracked files:

   ```sh
   git status --short --branch
   git diff
   git diff --cached
   git log --oneline -10
   ```

2. Review relevant history and split the changes into the smallest independently revertible units. Briefly explain non-obvious commit boundaries. Keep unrelated changes out of the commit. For moves or extractions, include both sides and update references.

3. Check the index before each unit: changes staged for a build may not belong to this commit. Preserve any staged-only edits before using `git restore --staged <path>` to remove changes outside the unit. If one file mixes units, restage only the current unit.

   Split through the index without rewriting working-tree files: stage selected hunks with `git apply --cached -v`, or a whole file with `git add <path>`. Do not use interactive staging, catch-all commands such as `git add -A` or `git add .`, or `git commit -a`/`-am`.

4. Write a Conventional Commit message with a concise, imperative subject. Follow user and repository language requirements; otherwise match representative recent commits. Follow existing Conventional Commit subject conventions, and use a scope only when requested or customary in the repository.

   When the subject and diff leave important reasons, constraints, tradeoffs, or impact unstated, explain them in a concise body. Decide body presence from the change, not recent commit lengths. Wrap body prose at 72 characters. For multiline messages, use `git commit --file -` with stdin to preserve actual line breaks.

   For formatter-only changes, use `chore: format`.

5. Review `git diff --cached` and run `git diff --cached --check`. Commit from the index, then verify with `git show HEAD` and `git status --short`. Repeat steps 3–5 for each unit.

6. Compare the combined commit diff and remaining changes with the original state: every intended change should be committed, and unrelated work preserved, including any saved staged-only edits.

Keep published review fixes as separate follow-up commits; amend only unpublished local mistakes or when explicitly requested.

## Push

Push only when requested, including `push=true`, after all commits are complete. Check the current branch, its upstream, and the commits to publish. Follow user and repository requirements for the remote and publication workflow, including an existing stack; set an upstream when needed. Let repository hooks run.
