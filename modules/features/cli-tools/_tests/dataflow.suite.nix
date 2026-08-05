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
    (repoRoot + "/modules/features/cli-tools/quirk.nix")
    (repoRoot + "/modules/features/agents/skills/quirk.nix")
    (repoRoot + "/modules/features/agents/base/quirk.nix")
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
        aggregated = import ../_lib/aggregate.nix { inherit lib pkgs; } cli-tools;
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
    testCliToolsBundleKeepsToolOwnedProjectionsTogether = evalTest (
      { config, features, ... }:
      let
        home = config.flake.homeConfigurations.tux.config;
        packageNames = map lib.getName home.home.packages;
        overlayPlan = (import ../../nixpkgs/_interface).mkOverlayPlan {
          inherit inputs;
          system = "x86_64-linux";
        };
      in
      {
        imports = [
          baseHome
          (repoRoot + "/modules/features/cli-tools/default.nix")
          (repoRoot + "/modules/features/cli-tools/reuse.nix")
          (repoRoot + "/modules/features/cli-tools/rg.nix")
          (repoRoot + "/modules/features/cli-tools/fd.nix")
          (repoRoot + "/modules/features/cli-tools/bat.nix")
          (repoRoot + "/modules/features/cli-tools/eza.nix")
          (repoRoot + "/modules/features/cli-tools/jq.nix")
          (repoRoot + "/modules/features/cli-tools/fzf.nix")
          (repoRoot + "/modules/features/ast-grep/default.nix")
          (repoRoot + "/modules/features/agents/skills/default.nix")
          (repoRoot + "/modules/features/agents/base/default.nix")
        ];
        den.default.homeManager.nixpkgs.overlays = overlayPlan.overlays;
        den.homes.x86_64-linux.tux = { };
        den.aspects.tux.includes = [
          features.cli-tools
          features.agent-skills-consumer
          features.agents-base
        ];

        expr = {
          toolPackagesPresent = lib.all (name: lib.elem name packageNames) [
            "reuse"
            "ripgrep"
            "fd"
            "bat"
            "eza"
            "jq"
            "ast-grep"
            "fzf"
          ];
          hasAstGrepSkill = home.dotfiles.agentSkills.externalSkills ? ast-grep;
          commandDecisions = {
            ast-grep = home.dotfiles.agentCommandPolicy.commands.ast-grep;
            bat = home.dotfiles.agentCommandPolicy.commands.bat;
            eza = home.dotfiles.agentCommandPolicy.commands.eza;
            fd = home.dotfiles.agentCommandPolicy.commands.fd.decision;
            jq = home.dotfiles.agentCommandPolicy.commands.jq;
            rg = home.dotfiles.agentCommandPolicy.commands.rg;
          };
        };
        expected = {
          toolPackagesPresent = true;
          hasAstGrepSkill = true;
          commandDecisions = {
            ast-grep = true;
            bat = true;
            eza = true;
            fd = true;
            jq = true;
            rg = true;
          };
        };
      }
    );

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
