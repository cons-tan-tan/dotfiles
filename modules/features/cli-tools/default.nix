{ config, ... }:
{
  flake.modules.homeManager.cli-tools-consumer =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      aggregated = import ./_lib/aggregate.nix { inherit lib pkgs; } config.dotfiles.cliTools;
    in
    {
      key = "modules/features/cli-tools/default.nix#homeManager.cli-tools-consumer";

      home.packages = aggregated.nixHomePackages;
    };

  flake.modules.homeManager.cli-tools = {
    key = "modules/features/cli-tools/default.nix#homeManager.cli-tools";
    # Baseline tool files contribute to this module directly, so adding a tool
    # does not require updating an import list. Keep independently reusable
    # features as named imports.
    imports = [
      config.flake.modules.homeManager.cli-tools-consumer
      config.flake.modules.homeManager.ast-grep
    ];
  };
}
