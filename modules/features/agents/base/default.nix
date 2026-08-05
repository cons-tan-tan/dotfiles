{
  lib,
  ...
}:
let
  policyRoot = ./_lib/command-policy;
in
{
  features.agents-base = {
    name = "feature/agents/base";

    homeManager =
      { config, pkgs, ... }:
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

        config.agentCommandPolicy =
          (import (policyRoot + "/rules.nix") { inherit lib; }).agentCommandPolicy;

        config.home.packages = [ pkgs.dotfilesPackages.shellfirm ];

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
}
