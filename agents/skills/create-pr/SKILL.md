---
name: create-pr
description: Prepares a branch, commits changes, pushes, and creates or updates a pull request. Use when the user asks to create or open a PR ("create a PR", "push this up and open a PR").
---

# Create PR

## PR Granularity

Group each PR around one reviewable purpose; it may contain multiple atomic commits. Split independent work into separate PRs even if it shares a branch, and stack only dependent work.

## PR Language and Format

Choose one language for the title's description (the text after the colon) and body prose using the first applicable rule:

1. Use the user's explicit PR language request; otherwise follow explicit repository PR language requirements. Instructions about the conversation language alone do not set the PR language.
2. Otherwise, inspect the user's recent PRs in the target repository (for the authenticated user, use `gh pr list --repo OWNER/REPO --author @me --state all --limit 5 --json title,body`). Only if the user has no PRs there, inspect a few recent PRs by other authors in that repository. Use the predominant language of the title descriptions and body prose, ignoring prefixes and headings.
3. Default to English if history is unavailable or shows no clear language convention.

Apply these rules when revising generated PR text as well. Preserve code and technical identifiers as written.

Use these format defaults, overriding only the fields explicitly prescribed by the user or repository (including required PR templates):

- Use the `commit` skill's Conventional Commit syntax and subject style for the PR title; the PR language rules above govern its description. Keep the prefix in English.
- Use English H2 labels for sections that help review: `## Summary`, `## What Changed`, `## Why`, `## Testing`, and `## Related Issues`. Keep additional headings and subheadings in English too. A prose language request does not change the prefix or heading labels.

Example titles: English `feat(agents): clarify PR language selection`; Japanese `feat(agents): PR の言語選択を明確にする`.

## Workflow

1. Inspect the current branch, status, target repository, and push remote. Check for an open PR matching the target repository and head repository/branch.

2. Use the repository's default branch as the base unless the user, the matching PR, or the stack specifies another target. Create a feature branch when working on the default branch; otherwise reuse a suitable branch. Follow repository branch naming conventions.

3. Review local changes (staged, unstaged, and untracked) and the complete PR diff against the intended base. Keep unrelated changes, temporary files, secrets, generated junk, and debug-only edits out of the PR.

4. Commit the intended changes with the `commit` skill. Run the relevant checks required by the change and repository, reusing results that still apply.

5. Prepare a PR title and body proportional to the change:

   - Apply PR Language and Format above. Explain what changed and why; a short paragraph is enough for a small focused change.
   - Include Testing only when required by the template or when it adds useful review context beyond CI, such as a manual behavior check. Summarize outcomes; one aggregate test command and its result may suffice. Omit command inventories and duplicate local results for checks covered by CI. Base any CI status claims on observed CI results, and disclose verification gaps that affect review.
   - Use `--body-file` (file or stdin) for multiline bodies. Do not encode line breaks as literal `\n` sequences in `--body`.

6. When visual evidence helps review and `gh pr create --help` lists `--attach`, attach real local screenshots or short videos. Prefer Markdown references to local paths in the body so alt text survives upload. For an existing PR, add media with `gh pr edit` or `gh pr comment`. See the [attachment documentation](https://gh.io/gh-attach).

7. Confirm the base and head match the reviewed diff, then publish:

   - Use `gh-stack` only when requested or when the branch is already stacked; follow its skill for branch relationships and publication. Adjust generated titles and bodies to match step 5, preserving stack footers.
   - For an ordinary PR, push to the selected remote and create the PR with the prepared title and body, or update the matching open PR.

8. Report the PR URL and current validation status. If publishing fails, inspect the error and remote state before retrying only the unfinished operation. A partial attachment failure can leave a successfully created PR.
