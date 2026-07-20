{
  runCommand,
  jq,
  yj,
  codex,
  hcom,
}:
{
  # Run hcom's own `hooks add` rather than hand-copying or re-implementing its
  # output format, so the definitions track the packaged version automatically.
  # Claude has no hook-trust mechanism, so its emitted settings are usable as-is.
  claudeHooks =
    runCommand "hcom-claude-hooks.json"
      {
        nativeBuildInputs = [
          hcom
          jq
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME/.claude"
        hcom hooks add claude >/dev/null 2>&1 || true
        if [ ! -f "$HOME/.claude/settings.json" ]; then
          echo "hcom did not generate ~/.claude/settings.json" >&2
          exit 1
        fi
        jq '{hooks, env, permissions}' "$HOME/.claude/settings.json" > "$out"
      '';

  # trusted_hash is computed by codex's own (undocumented) algorithm, so rather
  # than re-implement it we run hcom+codex and let codex's app-server RPC produce
  # it. Shaping uses yj/jq to avoid pulling in python. The state key embeds an
  # absolute path that differs between sandbox and $HOME, so we re-key by event
  # label here and rebuild the real path in codex/default.nix.
  codexHooks =
    runCommand "hcom-codex-hooks"
      {
        nativeBuildInputs = [
          hcom
          codex
          yj
          jq
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME/.codex" "$out"
        hcom hooks add codex >/dev/null 2>&1 || true
        test -f "$HOME/.codex/hooks.json" || { echo "hcom did not generate hooks.json" >&2; exit 1; }
        test -f "$HOME/.codex/config.toml" || { echo "hcom did not generate config.toml" >&2; exit 1; }
        cp "$HOME/.codex/hooks.json" "$out/hooks.json"
        yj -tj < "$HOME/.codex/config.toml" \
          | jq '.hooks.state
                | to_entries
                | map({ key: (.key | split(":")[-3]), value: .value })
                | from_entries' \
          > "$out/hooks-state.json"
      '';
}
