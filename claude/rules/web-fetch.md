# Web Fetch Strategy

When fetching web content, try methods in this order. Move to the next if the current one fails (e.g. 403, timeout, aborted):

1. WebFetch tool - Default. Try this first.
2. curl fallback - If WebFetch returns 403, retry with `curl-fetch -sL -A "claude-code/1.0" <url>`. Many 403s are caused by Cloudflare blocking the default `Claude-User` User-Agent. `curl-fetch` is a read-only HTTP(S) fetcher, not a general curl replacement. It allows GET/HEAD-style fetches, explicit `-o/--output` paths, literal `--write-out` formats, and basic retry/timeout/header controls. It blocks request mutation (`-X`, `-d`, `-F`), local file reads (`@file`, config/cookie/cert files), remote-derived filenames (`-O`, `-J`), curl state/trace files, proxy/destination overrides, and non-HTTP(S) protocols. Use raw `curl` with explicit approval for those cases.
3. `agent-browser` skill - Use the `agent-browser` skill for browser-based fetching.

## Social Media Posts (FxEmbed)

X/Twitter and Bluesky block direct fetching. Use [FxEmbed](https://github.com/FxEmbed/FxEmbed) proxy domains to read posts:

| Original domain | Replace with                       |
| --------------- | ---------------------------------- |
| `x.com`         | `fixupx.com` (or `xfixup.com`)     |
| `twitter.com`   | `fxtwitter.com` (or `twittpr.com`) |
| `bsky.app`      | `fxbsky.app`                       |

```
https://x.com/user/status/123           -> https://fixupx.com/user/status/123
https://twitter.com/user/status/123     -> https://fxtwitter.com/user/status/123
https://bsky.app/profile/user/post/abc  -> https://fxbsky.app/profile/user/post/abc
```

Important: FxEmbed responses contain embedded images and metadata that pollute the main context. Always fetch via a subagent using `curl-fetch -sL` to keep the main conversation clean.
