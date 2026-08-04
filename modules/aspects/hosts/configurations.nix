{ den, ... }:
{
  den.aspects.hosts.constantan = {
    name = "host/constantan";
    includes = [
      den.batteries.hostname
      den.aspects.environments.darwin
    ];
  };

  den.aspects.hosts.wsl = {
    name = "host/wsl";
    includes = [
      den.batteries.hostname
      den.aspects.environments.wsl
    ];
  };

  den.aspects.hosts.wsl-aarch64 = {
    name = "host/wsl-aarch64";
    includes = [
      den.batteries.hostname
      den.aspects.environments.wsl
    ];
  };
}
