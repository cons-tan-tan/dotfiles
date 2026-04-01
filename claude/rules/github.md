# GitHub Access Strategy

## Pre-approved Commands

The following `gh` subcommands are pre-approved and do not require user confirmation.
Prefer these over alternatives that need approval:

- `gh issue list|view`
- `gh pr list|view|diff|checks`
- `gh run list|view`
- `gh api-get` (Use instead of `gh api`. This alias forces `--method GET` to prevent unintended write operations.)

For other `gh` operations (e.g., `gh pr create`, `gh issue create`), user approval is required.

## Accessing GitHub Content

When accessing GitHub-hosted content (repository files, issues, PRs, etc.), prefer `gh` commands over WebFetch or curl.

## Tips
- If you use `gh do` command, you can pass GitHub credentials via environment variables. See `gh do --help` for more details.
