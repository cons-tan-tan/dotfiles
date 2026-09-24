{
  flake.modules.homeManager.shell-zoxide = {
    key = "modules/features/shell/zoxide.nix#homeManager.shell-zoxide";
    imports = [
      { programs.zoxide.enable = true; }
    ];
    dotfiles.cliTools = [
      {
        id = "zoxide";
        nix.route = "programs";
        winget = {
          packageId = "ajeetdsouza.zoxide";
          description = "zoxide";
        };
      }
    ];
  };
}
