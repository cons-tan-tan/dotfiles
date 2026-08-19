let
  packageArgs = builtins.functionArgs (import ../_packages/herdr/package.nix);
  fixturePin = {
    version = "1.2.3";
  };
  fixtureFamily = import ../_packages/herdr/default.nix {
    ghApiGet = null;
    herdrPin = fixturePin;
    mkPinnedAsset = _: { };
    callPackage =
      path: args:
      if path == ../_packages/herdr/package.nix then
        {
          package = args.herdrPin.version;
          platforms = [ ];
          src = null;
          version = args.herdrPin.version;
        }
      else
        { };
  };
in
{
  testHerdrFamilyForwardsPin = {
    expr = fixtureFamily.package;
    expected = fixturePin.version;
  };

  testLlmAgentsIsNotAccepted = {
    expr = builtins.hasAttr "llm-agents" packageArgs;
    expected = false;
  };
}
