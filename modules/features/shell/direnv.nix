{ ... }:
{
  features.shell-direnv = {
    name = "feature/shell/direnv";
    homeManager.programs.direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };
  };
}
