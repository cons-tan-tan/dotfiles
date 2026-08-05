{ den, ... }:
{
  den.aspects.environments.base = {
    name = "dotfiles-environment-base";
    includes = [ den.batteries.flake-scope ];
  };
}
