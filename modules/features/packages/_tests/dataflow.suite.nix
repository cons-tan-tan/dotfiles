{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../../../..,
}:
let
  testImports = lib.optional (inputs ? flake-parts) inputs.den.flakeOutputs.flake ++ [
    (inputs.den.namespace "features" false)
    {
      options.flake-file = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
    }
    (repoRoot + "/modules/quirks/cli-tools.nix")
  ];

  evalTest =
    module:
    (lib.evalModules {
      specialArgs = { inherit inputs; };
      modules = [
        inputs.den.flakeModules.denTest
        { denTest.imports = testImports; }
        (
          { denTest, ... }:
          {
            options.result = lib.mkOption { type = lib.types.raw; };
            config.result = denTest module;
          }
        )
      ];
    }).config.result;

  baseHome =
    { lib, ... }:
    {
      den.default.homeManager.home = {
        username = "test";
        homeDirectory = lib.mkForce "/home/test";
        stateVersion = "25.11";
      };
    };

  consumer = {
    homeManager =
      {
        cli-tools,
        lib,
        pkgs,
        ...
      }:
      let
        aggregated = import ../_lib/aggregate-cli-tools.nix { inherit lib pkgs; } cli-tools;
      in
      {
        home.sessionVariables = {
          CLI_TOOL_IDS = builtins.toJSON (map (entry: entry.id) aggregated.checked);
          CLI_TOOL_NIX_PACKAGES = builtins.toJSON (map lib.getName aggregated.nixHomePackages);
          CLI_TOOL_WINGET_IDS = builtins.toJSON (map (entry: entry.id) aggregated.winget);
        };
      };
  };

  tests = {
    testQuirkMergesIndependentOfIncludeOrderAndKeepsHomeScopesIsolated = evalTest (
      {
        config,
        den,
        ...
      }:
      let
        describe =
          name:
          let
            variables = config.flake.homeConfigurations.${name}.config.home.sessionVariables;
          in
          {
            ids = builtins.fromJSON variables.CLI_TOOL_IDS;
            nixPackages = builtins.fromJSON variables.CLI_TOOL_NIX_PACKAGES;
            wingetIds = builtins.fromJSON variables.CLI_TOOL_WINGET_IDS;
          };
      in
      {
        imports = [ baseHome ];
        den.homes.x86_64-linux = {
          pingu = { };
          tux = { };
        };
        den.aspects.alpha.cli-tools = [
          {
            id = "alpha";
            nix = {
              route = "home-packages";
              nixpkgsAttr = "reuse";
            };
          }
        ];
        den.aspects.beta.cli-tools = [
          {
            id = "beta";
            winget.packageId = "Example.Beta";
          }
        ];
        den.aspects.pingu = {
          includes = [ consumer ];
          cli-tools = [
            {
              id = "pingu";
              winget.packageId = "Example.Pingu";
            }
          ];
        };
        den.aspects.tux.includes = [
          den.aspects.beta
          consumer
          den.aspects.alpha
        ];

        expr = {
          pingu = describe "pingu";
          tux = describe "tux";
        };
        expected = {
          pingu = {
            ids = [ "pingu" ];
            nixPackages = [ ];
            wingetIds = [ "pingu" ];
          };
          tux = {
            ids = [
              "beta"
              "alpha"
            ];
            nixPackages = [ "reuse" ];
            wingetIds = [ "beta" ];
          };
        };
      }
    );
  };

  failureCases = { };
in
if caseName == null then
  {
    inherit failureCases tests;
  }
else
  failureCases.${caseName}.expression
