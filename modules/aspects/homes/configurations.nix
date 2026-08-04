{ den, ... }:
{
  den.aspects.homes.standalone-linux = {
    name = "home/standalone-linux";
    includes = [
      den.batteries.define-user
      (den.batteries.user-shell "zsh")
      den.aspects.environments.linux
    ];
  };

  den.aspects.homes.standalone-wsl = {
    name = "home/standalone-wsl";
    includes = [
      den.batteries.define-user
      (den.batteries.user-shell "zsh")
      den.aspects.environments.standalone-wsl
    ];
  };
}
