# Central place for agent model IDs. Keep this out of update-pins: switching
# models is a reviewed product/runtime choice, not a mechanical dependency bump.
{
  claude = {
    main = "claude-opus-4-7[1m]";
    sonnet = "claude-sonnet-5";
  };

  codex = {
    model = "gpt-5.6-sol";
    reasoningEffort = "high";
  };

  pi = {
    provider = "openai-codex";
    model = "gpt-5.6-sol";
    thinkingLevel = "high";
  };

  opencode = {
    model = "openai/gpt-5.6-sol";
    reasoningEffort = "high";
  };
}
