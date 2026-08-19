{ pkgs }:
let
  package = pkgs.dotfilesPackages.agent-slack;
  system = pkgs.stdenv.hostPlatform.system;
  asset = {
    name = "agent-slack-fixture-${system}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
  injectedPackage = package.override {
    pin.assets.${system} = asset;
  };
in
{
  testAgentSlackPinPropagatesToReleaseAsset = {
    expr = {
      url = builtins.head injectedPackage.src.urls;
      hash = injectedPackage.src.outputHash;
    };
    expected = {
      url = "https://github.com/stablyai/agent-slack/releases/download/v${injectedPackage.version}/${asset.name}";
      inherit (asset) hash;
    };
  };

  testAgentSlackOwnsItsUpdateScript = {
    expr = builtins.isString package.updateScript && package.updateScriptName == "agent-slack";
    expected = true;
  };
}
