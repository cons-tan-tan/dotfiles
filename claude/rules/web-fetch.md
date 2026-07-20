# Web Fetch Strategy

Unless a source-specific rule applies, fetch general web content in this order. Continue when a method fails or returns incomplete content:

1. WebFetch tool - Use this by default.
2. curl fallback - Retry with `curl-fetch -fsSL -A "claude-code/1.0" <url>`. This is a GET/HEAD-only HTTP(S) wrapper with a small option allowlist. If a required read-only fetch is unsupported, use `agent-browser` or request approval for an explicitly scoped raw `curl` command.
3. `agent-browser` skill - Use this when fetching requires browser rendering or interaction.

## Social Media Posts (FxEmbed)

For public X/Twitter and Bluesky posts, skip the general sequence and use the [FxEmbed v2 JSON API](https://docs.fxembed.com/api/introduction/). Do not use the embed hosts (`fixupx.com`, `fxtwitter.com`, `fxbsky.app`), which may redirect to the origin site; use the API hosts below.

| Original URL                                     | Fetch via                                         |
| ------------------------------------------------ | ------------------------------------------------- |
| `x.com` or `twitter.com` `/<handle>/status/<id>` | `https://api.fxtwitter.com/2/status/<id>`         |
| `bsky.app/profile/<handle>/post/<rkey>`          | `https://api.fxbsky.app/2/status/<handle>/<rkey>` |

Pipe `curl-fetch -sSL --fail-with-body` into a `jq -e` filter that requires `.code == 200` and `.status != null` and emits only the needed fields. For API errors, report only `.code` and `(.message // .status.message)`; never expose the full response.

Both APIs place the requested post under `.status`. Useful fields are `.status.text`, `.status.article.title`, and `.status.article.content.blocks[]?.text` (X Article text blocks, when present).

X Article URLs do not map directly to the API. Identify a containing post with WebSearch or `agent-browser`, or report that it cannot be identified reliably.
