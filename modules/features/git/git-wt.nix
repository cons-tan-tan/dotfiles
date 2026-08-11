{ features, ... }:
{
  features.git-wt = {
    name = "feature/git-wt";
    includes = [ features.git ];
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
