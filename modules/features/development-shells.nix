{ den, ... }:
{
  den.aspects.development-shells.devShells =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      updatePinsCore = pkgs.callPackage ../../nix/apps/update-pins { };
      applySecretsCore = pkgs.callPackage ../../nix/apps/apply-secrets { };
      applyNixSettingsCore = pkgs.callPackage ../../nix/apps/apply-nix-settings { };
      safeFetch = pkgs.callPackage ../../nix/packages/safe-fetch { };
      curlFetch = pkgs.dotfilesPackages.curl-fetch;
      ghApiGet = pkgs.dotfilesPackages.gh-api-get;
    in
    {
      default = pkgs.mkShell {
        APPLY_SECRETS_TEST_BIN = lib.getExe applySecretsCore;
        APPLY_NIX_SETTINGS_TEST_BIN = lib.getExe applyNixSettingsCore;
        CURL_FETCH_PUBLIC_BIN = lib.getExe curlFetch;
        CURL_FETCH_TEST_BIN = "${safeFetch.core}/bin/curl-fetch";
        GH_API_GET_EXTENSION_ROOT = ghApiGet;
        GH_API_GET_PUBLIC_BIN = lib.getExe ghApiGet;
        GH_API_GET_TEST_BIN = "${safeFetch.core}/bin/gh-api-get";
        UPDATE_PINS_TEST_BIN = lib.getExe updatePinsCore;
        packages = with pkgs; [
          applySecretsCore
          applyNixSettingsCore
          bats
          cargo
          clippy
          ghApiGet
          shellcheck
          jq
          rustc
          rustfmt
          curlFetch
          sops
          reuse
          updatePinsCore
          yq-go
          zip
        ];
      };

      rust = pkgs.mkShell {
        packages = with pkgs; [
          cargo
          clippy
          git
          rustc
          rustfmt
        ];
      };
    };

  den.schema.flake-parts.includes = [ den.aspects.development-shells ];
}
