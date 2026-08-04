{
  den,
  features,
  lib,
  ...
}:
let
  policyRoot = ./_lib/command-policy;
in
{
  features.agents-base = {
    name = "feature/agents/base";
    includes = [ den.aspects.agent-command-policy-forward ];

    agentCommandPolicy =
      { lib, ... }:
      (import (policyRoot + "/rules.nix") { inherit lib; }).agentCommandPolicy;

    homeManager =
      { config, ... }:
      let
        policy = config.dotfiles.agentCommandPolicy;
      in
      {
        imports = [
          (policyRoot + "/options.nix")
          (lib.mkAliasOptionModule
            [
              "dotfiles"
              "agentCommandPolicy"
            ]
            [ "agentCommandPolicy" ]
          )
        ];

        options.dotfiles.agentCommandPolicyCompiled = lib.mkOption {
          type = lib.types.raw;
          readOnly = true;
          internal = true;
          description = "Validated projections of the merged agent command policy.";
        };

        options.dotfiles.agentIntegrations.hcom = lib.mkOption {
          internal = true;
          default = null;
          description = "hcom artifacts available when dotfiles.hcom.enable is enabled.";
          type = lib.types.nullOr (
            lib.types.submodule {
              options = {
                package = lib.mkOption { type = lib.types.package; };
                claudeHooks = lib.mkOption { type = lib.types.package; };
                codexHooks = lib.mkOption { type = lib.types.package; };
              };
            }
          );
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

  features.agents-default = {
    name = "feature/agents/default";
    includes = [
      features.agents-base
      features.agent-skills
      features.agent-guidance
      features.agent-claude
      features.agent-codex
      features.agent-hcom
      features.agent-herdr
      features.agent-hunk
      features.agent-opencode
      features.agent-pi
    ];
  };
}
