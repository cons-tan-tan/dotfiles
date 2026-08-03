{
  flake,
  pkgs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  shell = flake.devShells.${system}.default;
  updatePinsCore = pkgs.callPackage ../apps/update-pins { };
  applySecretsCore = pkgs.callPackage ../apps/apply-secrets { };
  applyNixSettingsCore = pkgs.callPackage ../apps/apply-nix-settings { };
  safeFetch = pkgs.callPackage ../packages/safe-fetch { };
  curlFetch = pkgs.dotfilesPackages.curl-fetch;
  ghApiGet = pkgs.dotfilesPackages.gh-api-get;
in
{
  testDefaultShellEnvironment = {
    expr = {
      inherit (shell)
        APPLY_NIX_SETTINGS_TEST_BIN
        APPLY_SECRETS_TEST_BIN
        CURL_FETCH_PUBLIC_BIN
        CURL_FETCH_TEST_BIN
        GH_API_GET_EXTENSION_ROOT
        GH_API_GET_PUBLIC_BIN
        GH_API_GET_TEST_BIN
        UPDATE_PINS_TEST_BIN
        ;
    };
    expected = {
      APPLY_NIX_SETTINGS_TEST_BIN = pkgs.lib.getExe applyNixSettingsCore;
      APPLY_SECRETS_TEST_BIN = pkgs.lib.getExe applySecretsCore;
      CURL_FETCH_PUBLIC_BIN = pkgs.lib.getExe curlFetch;
      CURL_FETCH_TEST_BIN = "${safeFetch.core}/bin/curl-fetch";
      GH_API_GET_EXTENSION_ROOT = ghApiGet;
      GH_API_GET_PUBLIC_BIN = pkgs.lib.getExe ghApiGet;
      GH_API_GET_TEST_BIN = "${safeFetch.core}/bin/gh-api-get";
      UPDATE_PINS_TEST_BIN = pkgs.lib.getExe updatePinsCore;
    };
  };

  testShellsUseLegacyPackageContext = {
    expr = builtins.all pkgs.lib.isDerivation [
      flake.devShells.${system}.default
      flake.devShells.${system}.rust
    ];
    expected = true;
  };
}
