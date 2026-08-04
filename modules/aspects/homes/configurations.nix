{ den, features, ... }:
{
  den.aspects.homes.standalone-linux = {
    name = "home/standalone-linux";
    includes = [
      den.batteries.define-user
      den.aspects.environments.linux
      features.common-home
      features.agents-default
    ];
  };

  den.aspects.homes.standalone-wsl = {
    name = "home/standalone-wsl";
    includes = [
      den.batteries.define-user
      den.aspects.environments.standalone-wsl
      features.common-home
      features.agents-default
    ];
  };
}
