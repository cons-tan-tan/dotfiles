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
    imports = [
      config.flake.modules.homeManager.cli-tools-consumer
      config.flake.modules.homeManager.cli-tool-reuse
      config.flake.modules.homeManager.cli-tool-rg
      config.flake.modules.homeManager.cli-tool-fd
      config.flake.modules.homeManager.cli-tool-bat
      config.flake.modules.homeManager.cli-tool-eza
      config.flake.modules.homeManager.cli-tool-jq
      config.flake.modules.homeManager.ast-grep
      config.flake.modules.homeManager.cli-tool-fzf
    ];
  };
}
