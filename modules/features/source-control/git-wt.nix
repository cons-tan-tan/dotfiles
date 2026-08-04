{ features, ... }:
{
  features.source-control-git-wt = {
    name = "feature/source-control/git-wt";
    includes = [ features.source-control-git ];
    homeManager =
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
      };
  };
}
