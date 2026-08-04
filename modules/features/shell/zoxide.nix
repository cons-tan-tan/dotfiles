{ ... }:
{
  features.shell-zoxide = {
    name = "feature/shell/zoxide";
    homeManager.programs.zoxide.enable = true;
  };
}
