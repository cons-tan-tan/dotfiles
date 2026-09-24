{
  config,
  ...
}:
{
  flake.modules.homeManager.shell-zsh = {
    key = "modules/features/shell/zsh.nix#homeManager.shell-zsh";
    imports = [
      config.flake.modules.homeManager.shell-direnv
      config.flake.modules.homeManager.shell-starship
      config.flake.modules.homeManager.shell-zoxide
    ];
    programs.zsh.enable = true;
  };
}
