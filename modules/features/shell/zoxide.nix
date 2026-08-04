{ ... }:
{
  features.shell-zoxide = {
    name = "feature/shell/zoxide";
    cli-tools = [
      {
        id = "zoxide";
        nix.route = "programs";
        winget = {
          packageId = "ajeetdsouza.zoxide";
          description = "zoxide";
        };
      }
    ];
    homeManager.programs.zoxide.enable = true;
  };
}
