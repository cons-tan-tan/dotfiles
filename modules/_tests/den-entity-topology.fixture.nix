{ den, lib, ... }:
{
  den.aspects.synthetic-host-policy = {
    name = "synthetic-host-policy-probe";
    homeManager =
      { host, ... }:
      {
        home.sessionVariables.DEN_HOST_POLICY_EVALUATED = "1";
      }
      // lib.optionalAttrs (host.name == "wsl") {
        home.sessionVariables.DEN_HOST_POLICY_LEAK = "1";
      };
  };

  den.aspects.synthetic-isolation = {
    name = "synthetic-context-isolation-probe";
    includes = [ den.aspects.synthetic-host-policy ];
    homeManager =
      {
        host,
        osConfig ? null,
        user,
        ...
      }:
      {
        home = {
          username = user.userName;
          homeDirectory = "/home/${user.userName}";
          stateVersion = "24.11";
          sessionVariables = {
            DEN_CONTEXT_HOST = host.name;
            DEN_CONTEXT_USER = user.userName;
            DEN_CONTEXT_OS_CONFIG = if osConfig == null then "null" else "set";
          };
        };
      };
  };

  den.aspects.arg-collision = {
    name = "class-module-arg-collision";
    nixos.imports = [
      { _module.args.host = "from-module-system"; }
      (
        { host, ... }:
        {
          networking.hostName = host.name;
        }
      )
    ];
  };

  den.homes.x86_64-linux."tux@standalone-wsl" = {
    aspect = den.aspects.synthetic-isolation;
    intoAttr = [
      "homeConfigurations"
      "synthetic-isolation-probe"
    ];
  };

  den.hosts.x86_64-linux.collision.aspect = den.aspects.arg-collision;
}
