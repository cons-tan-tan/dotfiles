let
  familyArgs = builtins.functionArgs (import ./default.nix);
  packageArgs = builtins.functionArgs (import ./package.nix);
  fixturePin = {
    version = "1.2.3";
  };
  fixtureFamily = import ./default.nix {
    herdrPin = fixturePin;
    callPackage =
      path: args:
      if path == ./package.nix then
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
  testHerdrFamilyPinIsInjectable = {
    expr = familyArgs ? herdrPin;
    expected = true;
  };

  testHerdrPinIsInjectable = {
    expr = packageArgs ? herdrPin;
    expected = true;
  };

  testHerdrFamilyForwardsPin = {
    expr = fixtureFamily.package;
    expected = fixturePin.version;
  };

  testLlmAgentsIsNotAccepted = {
    expr = builtins.hasAttr "llm-agents" packageArgs;
    expected = false;
  };
}
