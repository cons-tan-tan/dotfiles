{ config, ... }:
{
  flake.modules.homeManager.git-wt = {
    key = "modules/features/git/git-wt.nix#homeManager.git-wt";
    imports = [
      config.flake.modules.homeManager.git
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          home.packages = [ pkgs.git-wt ];
          programs.zsh.initContent = lib.mkIf config.programs.zsh.enable ''
            eval "$(${lib.getExe pkgs.git-wt} --init zsh)"
          '';
        }
      )
    ];
  };
}
