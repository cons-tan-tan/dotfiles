{
  lib,
  username,
}:
let
  nixDaemonSettings = import ./nix-daemon-settings.nix { inherit username; };

  renderNixConfValue =
    value:
    if builtins.isList value then
      lib.concatStringsSep " " (map toString value)
    else if builtins.isBool value then
      lib.boolToString value
    else
      toString value;

  settings = {
    extra-trusted-users = nixDaemonSettings.extraTrustedUsers;
    extra-substituters = nixDaemonSettings.extraSubstituters;
    extra-trusted-substituters = nixDaemonSettings.extraTrustedSubstituters;
    extra-trusted-public-keys = nixDaemonSettings.extraTrustedPublicKeys;
  };
in
{
  inherit settings;

  text =
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: "${name} = ${renderNixConfValue value}") settings
    )
    + "\n";
}
