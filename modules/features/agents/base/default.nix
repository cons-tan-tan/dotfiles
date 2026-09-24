{
  config,
  lib,
  ...
}:
let
  policyRoot = ./_lib/command-policy;
in
{
  flake.modules.homeManager.agent-command-policy-defaults = {
    key = "modules/features/agents/base/default.nix#homeManager.agent-command-policy-defaults";
    dotfiles.agentCommandPolicyContributions = [
      {
        owner = "feature/agents/command-policy/defaults";
        policy = {
          shell.redirection.emptyFile = false;
          shellfirm = {
            enabled = true;
            minimumSeverity = "High";
            categories = {
              aws = true;
              docker = true;
              fs = true;
              gcp = true;
              git = true;
              github = true;
              kubernetes = true;
              network = true;
              npm = true;
              shell = true;
            };
            ruleNamespaces = {
              fs-strict = false;
              git-strict = false;
              kubernetes-strict = false;
            };
            rules.fs.flush_file_content = false;
          };
        };
      }
    ];
  };

  flake.modules.homeManager.agents-base = {
    key = "modules/features/agents/base/default.nix#homeManager.agents-base";
    imports = [
      config.flake.modules.homeManager.agent-command-policy-defaults
      (
        {
          config,
          pkgs,
          ...
        }:
        let
          aggregated = import (policyRoot + "/aggregate.nix") {
            inherit lib;
          } config.dotfiles.agentCommandPolicyContributions;
          policy = config.dotfiles.agentCommandPolicy;
        in
        {
          imports = [
            ./_interface/command-policy-options.nix
            (lib.mkAliasOptionModule
              [
                "dotfiles"
                "agentCommandPolicy"
              ]
              [ "agentCommandPolicy" ]
            )
          ];
          config.agentCommandPolicy = lib.mkMerge (
            map (module: module.config.agentCommandPolicy) aggregated.modules
          );

          config.home.packages = [ pkgs.dotfilesPackages.shellfirm ];

          options.dotfiles.agentCommandPolicyCompiled = lib.mkOption {
            type = lib.types.raw;
            readOnly = true;
            internal = true;
            description = "Validated projections of the merged agent command policy.";
          };

          config.dotfiles.agentCommandPolicyCompiled = import (policyRoot + "/compiler.nix") {
            inherit lib;
            inherit (policy)
              commandGrammars
              commands
              shell
              shellfirm
              ;
          };
        }
      )
    ];
  };
}
