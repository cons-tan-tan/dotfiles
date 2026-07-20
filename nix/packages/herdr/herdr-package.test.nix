let
  packageArgs = builtins.functionArgs (import ./default.nix);
in
{
  testHerdrPinIsInjectable = {
    expr = packageArgs ? herdrPin;
    expected = true;
  };

  testLlmAgentsIsNotAccepted = {
    expr = builtins.hasAttr "llm-agents" packageArgs;
    expected = false;
  };
}
