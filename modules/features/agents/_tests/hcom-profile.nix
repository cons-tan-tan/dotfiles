{
  environment,
  inputs,
  lib,
  repoRoot ? ../../../..,
  system,
}:
let
  agentsRoot = repoRoot + "/modules/features/agents";
  testImports = lib.optional (inputs ? flake-parts) inputs.den.flakeOutputs.flake ++ [
    (inputs.den.namespace "features" false)
    {
      options.flake-file = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
    }
    (repoRoot + "/modules/classes/agent-command-policy.nix")
    (repoRoot + "/modules/quirks/agent-skills.nix")
  ];
  overlayPlan = import (repoRoot + "/nix/lib/mk-overlays.nix") { inherit inputs; } system;
  evaluated =
    (lib.evalModules {
      specialArgs = { inherit inputs; };
      modules = [
        inputs.den.flakeModules.denTest
        { denTest.imports = testImports; }
        (
          { denTest, ... }:
          {
            options.result = lib.mkOption { type = lib.types.raw; };
            config.result = denTest (
              {
                config,
                features,
                ...
              }:
              {
                imports = [
                  (agentsRoot + "/base.nix")
                  (agentsRoot + "/claude.nix")
                  (agentsRoot + "/codex.nix")
                  (agentsRoot + "/guidance.nix")
                  (agentsRoot + "/hcom.nix")
                  (agentsRoot + "/herdr.nix")
                  (agentsRoot + "/hunk.nix")
                  (agentsRoot + "/opencode.nix")
                  (agentsRoot + "/pi.nix")
                  (agentsRoot + "/skills.nix")
                ];

                den.default.homeManager = {
                  home = {
                    username = "test";
                    homeDirectory = "/home/test";
                    stateVersion = "25.11";
                  };
                  dotfiles.agentEnvironment = {
                    inherit environment;
                    source = toString repoRoot;
                    windows.homedir = lib.mkIf (environment == "wsl") "/mnt/c/Users/test";
                  };
                  nixpkgs.overlays = overlayPlan.overlays;
                };
                den.homes.${system}.hcom = { };
                den.aspects.hcom.includes = [
                  features.agents-default
                  features.agent-hcom
                ];
                expr = config.flake.homeConfigurations.hcom.activationPackage;
              }
            );
          }
        )
      ];
    }).config.result;
in
evaluated.expr
