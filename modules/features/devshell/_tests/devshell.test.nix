{
  flake,
  pkgs,
}:
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  defaultShell = flake.devShells.${system}.default;
  rustShell = flake.devShells.${system}.rust;
  inputPaths = shell: map (input: input.drvPath) (shell.nativeBuildInputs or [ ]);
  containsAll =
    shell: packages: builtins.all (package: builtins.elem package.drvPath (inputPaths shell)) packages;
  containsNone =
    shell: packages:
    builtins.all (package: !(builtins.elem package.drvPath (inputPaths shell))) packages;
  fixtureEnvironmentNames = [
    "APPLY_NIX_SETTINGS_TEST_BIN"
    "APPLY_SECRETS_TEST_BIN"
    "CURL_FETCH_PUBLIC_BIN"
    "CURL_FETCH_TEST_BIN"
    "GH_API_GET_EXTENSION_ROOT"
    "GH_API_GET_PUBLIC_BIN"
    "GH_API_GET_TEST_BIN"
    "NIX_MUTATION_TEST_BIN"
    "UPDATE_PINS_TEST_BIN"
  ];
  rustTools = with pkgs; [
    cargo
    clippy
    rustc
    rustfmt
  ];
  sourceTools = with pkgs; [
    bats
    git
    jq
    (callPackage ../_packages/nix-mutation-test { })
    reuse
    shellcheck
    sops
    yq-go
  ];
in
{
  testPublicShellsUseFlakePartsPackageContext = {
    expr = builtins.all lib.isDerivation [
      defaultShell
      rustShell
    ];
    expected = true;
  };

  testDefaultShellDoesNotExportPackageFixtureEnvironment = {
    expr = builtins.all (name: !(builtins.hasAttr name defaultShell)) fixtureEnvironmentNames;
    expected = true;
  };

  testDefaultShellContainsSourceEditingTools = {
    expr = containsAll defaultShell sourceTools;
    expected = true;
  };

  testRustCompilerToolsAreIsolatedToRustShell = {
    expr = containsNone defaultShell rustTools && containsAll rustShell rustTools;
    expected = true;
  };
}
