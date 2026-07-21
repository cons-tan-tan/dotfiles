# Central place for agent model IDs. Keep this out of update-pins: switching
# models is a reviewed product/runtime choice, not a mechanical dependency bump.
let
  codexFamilyModel = "gpt-5.6-sol";
in
{
  claude = {
    main = "claude-opus-4-7[1m]";
    sonnet = "claude-sonnet-5";
  };

  codex = {
    model = codexFamilyModel;
    reasoningEffort = "high";
  };

  pi = {
    provider = "openai-codex";
    model = codexFamilyModel;
    thinkingLevel = "high";
  };

  opencode = {
    model = "openai/${codexFamilyModel}";
    reasoningEffort = "high";
  };
}
