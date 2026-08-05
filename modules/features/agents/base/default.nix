{
  features,
  lib,
  ...
}:
let
  policyRoot = ./_lib/command-policy;
in
{
  features.agent-command-policy-defaults = {
    name = "feature/agents/command-policy/defaults";
    agent-command-policy = [
      {
        source = "feature/agents/command-policy/defaults";
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

  features.agents-base = {
    name = "feature/agents/base";
    includes = [ features.agent-command-policy-defaults ];

    homeManager =
      {
        agent-command-policy,
        config,
        pkgs,
        ...
      }:
      let
        aggregated = import (policyRoot + "/aggregate.nix") {
          inherit lib;
        } agent-command-policy;
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
        ]
        ++ aggregated.modules;

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
            commands
            shell
            shellfirm
            ;
        };
      };
  };
}
