{
  den,
  lib,
  ...
}:
{
  features.platform-user =
    {
      host,
      user,
      ...
    }:
    let
      environment = host.dotfiles.environment;
    in
    {
      name = "feature/platform/user/${environment}";
      includes = lib.optionals (environment == "darwin" && user.dotfiles.primary) [
        den.batteries.primary-user
      ];
    }
    // lib.optionalAttrs (environment == "wsl") {
      # NixOS-WSL grants its default user wheel access. Avoid primary-user here
      # because it would additionally grant networkmanager; the project only
      # adds the Docker group and otherwise preserves the upstream privileges.
      wsl.defaultUser = user.userName;
      nixos.users.users.${user.userName} = {
        linger = true;
        extraGroups = [ "docker" ];
      };
    };
}
