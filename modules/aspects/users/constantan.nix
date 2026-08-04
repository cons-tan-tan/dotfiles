{ den, lib, ... }:
let
  darwinPrimaryUser =
    { host, user, ... }:
    {
      name = "darwin-primary-user";
    }
    // lib.optionalAttrs (host.class == "darwin") (den.batteries.primary-user { inherit host user; });
in
{
  den.aspects.users.constantan = {
    name = "user/constantan";
    includes = [
      den.batteries.define-user
      (den.batteries.user-shell "zsh")
      den.batteries.host-aspects
      darwinPrimaryUser
    ];

    # NixOS-WSL itself grants wheel to its default user. The Darwin-only guard
    # here prevents primary-user from additionally granting networkmanager.
  };
}
