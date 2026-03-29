# Preferred Tools

Use these tools instead of their standard alternatives:

| Tool             | Replaces | Description         |
| ---------------- | -------- | ------------------- |
| `rg`             | grep     | Fast search         |
| `fd`             | find     | File finder         |
| `bat`            | cat      | Syntax highlighting |
| `eza`            | ls       | Git-aware listing   |
| `jq`             | -        | JSON processor      |
| `gh`             | git      | GitHub CLI          |

## Tips

- if you use `gh do` command, you can pass github credentials via environment variables. See `gh do --help` for more details.
- Use `gh api-get` instead of `gh api` to fetch data from the GitHub API. This alias forces `--method GET` to prevent unintended write operations.
