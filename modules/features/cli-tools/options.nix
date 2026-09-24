{ lib, ... }:
{
  flake.modules.homeManager.cli-tools-consumer = {
    key = "modules/features/cli-tools/options.nix#homeManager.cli-tools-consumer";
    options.dotfiles.cliTools = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "CLI declarations supplied by selected features; validated before Nix and WinGet projection.";
    };
  };
}
