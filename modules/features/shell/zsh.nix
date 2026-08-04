{
  den,
  features,
  ...
}:
{
  features.shell-zsh = {
    name = "feature/shell/zsh";
    includes = [
      (den.batteries.user-shell "zsh")
      features.shell-direnv
      features.shell-starship
      features.shell-zoxide
    ];
  };
}
