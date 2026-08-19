{ pkgs }:
let
  package = pkgs.dotfilesPackages.agent-browser;
  system = pkgs.stdenv.hostPlatform.system;
  asset = {
    name = "agent-browser-fixture-${system}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
  injectedPackage = package.override {
    pin.assets.${system} = asset;
  };
in
{
  testAgentBrowserPinPropagatesToReleaseAsset = {
    expr = {
      url = builtins.head injectedPackage.src.urls;
      hash = injectedPackage.src.outputHash;
    };
    expected = {
      url = "https://github.com/vercel-labs/agent-browser/releases/download/v${injectedPackage.version}/${asset.name}";
      inherit (asset) hash;
    };
  };

  testAgentBrowserOwnsItsUpdateScript = {
    expr = builtins.isString package.updateScript && package.updateScriptName == "agent-browser";
    expected = true;
  };
}
