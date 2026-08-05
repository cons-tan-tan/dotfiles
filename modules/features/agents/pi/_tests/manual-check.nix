{
  ciCheck,
  currentTargets,
  flake,
  lib,
  pkgs,
  username,
}:
let
  payload = import ../_interface/payload.nix;
  commandPolicyInterface = import ../../base/_interface/command-policy.nix;
  repositoryHome =
    if pkgs.stdenv.hostPlatform.isDarwin then
      flake.darwinConfigurations.${currentTargets.darwin}.config.home-manager.users.${username}
    else
      flake.homeConfigurations.${currentTargets.home.linux}.config;
  agentCommandPolicy = repositoryHome.dotfiles.agentCommandPolicyCompiled;
  agentCommandGuardHook = commandPolicyInterface.mkGuard {
    inherit lib pkgs;
    policy = agentCommandPolicy.guardPolicy;
  };
  piAgentCommandGuard = pkgs.replaceVars payload.agentCommandGuard {
    guardBin = lib.getExe agentCommandGuardHook.guard;
    guardPolicy = agentCommandGuardHook.policyFile;
  };
in
{
  owner = "Pi package checks";
  artifacts = [ ];
  checks = {
    pi-package-layout = ciCheck.annotate (ciCheck.targets.both "package-smoke") (
      pkgs.runCommand "pi-package-layout" { } ''
        test -f ${pkgs.pi}/libexec/pi/package.json
        test -x ${pkgs.pi}/libexec/pi/pi
        touch "$out"
      ''
    );
    pi-command-guard-extension = ciCheck.annotate (ciCheck.targets.both "rust-and-bats") (
      pkgs.runCommand "pi-command-guard-extension"
        {
          nativeBuildInputs = [ pkgs.pi ];
        }
        ''
          export PI_CODING_AGENT_DIR="$TMPDIR/pi"
          pi --offline --no-session \
            --extension ${piAgentCommandGuard} \
            --list-models __agent_command_guard_smoke__ \
            > "$TMPDIR/output"
          touch "$out"
        ''
    );
  };
}
