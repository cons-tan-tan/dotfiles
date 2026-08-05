## GitHub Access Strategy

### Accessing GitHub Content

When accessing or operating on GitHub repositories, issues, pull requests, Actions, and APIs, prefer `gh` over web fetch tools or curl.

For read-only API requests, prefer `gh api-get` over `gh api` to prevent unintended write operations.

### Reading GitHub Repositories

For a few known paths, use `gh repo read-file` or `gh repo read-dir` instead of cloning.

When repository-wide search, history, builds, or tests make a local checkout more efficient, use `gh repo clone` into a temporary directory under `/tmp`.

### Tips

- `gh do` can pass GitHub credentials through environment variables. See `gh do --help` for details.
