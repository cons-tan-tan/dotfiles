{
  lib,
  nh,
  nix,
  scope ? "user",
  writeShellApplication,
}:
let
  cleanupPolicy = import ../../_lib/cleanup-policy.nix;
in
assert lib.assertOneOf "nh cleanup scope" scope [
  "all"
  "user"
];
writeShellApplication {
  name = "nh-clean-${scope}";
  runtimeInputs = [
    nh
    nix
  ];

  # nh invokes nix by name even when nh itself is addressed by an absolute
  # store path. Keep both tools in the wrapper closure so services do not
  # depend on an interactive or distribution-specific PATH.
  text = ''
    exec nh clean ${lib.escapeShellArg scope} ${lib.escapeShellArgs cleanupPolicy.arguments} "$@"
  '';
}
