{
  lib,
  nh,
  nix,
  writeShellApplication,
}:
let
  cleanupPolicy = import ../../lib/nh-clean-policy.nix;
in
writeShellApplication {
  name = "nh-clean-user";
  runtimeInputs = [
    nh
    nix
  ];

  # nh invokes nix by name even when nh itself is addressed by an absolute
  # store path. Keep both tools in the wrapper closure so services do not
  # depend on an interactive or distribution-specific PATH.
  text = ''
    exec nh clean user ${lib.escapeShellArgs cleanupPolicy.arguments} "$@"
  '';
}
