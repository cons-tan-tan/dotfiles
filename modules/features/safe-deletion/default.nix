{
  features,
  lib,
  ...
}:
let
  commandPolicy = import ../agents/base/_interface/command-policy.nix;
  mkProfile = commandPolicy.mkAbbreviatedLongOptionProfile lib;
  trashGuidance = "Use `trash` instead of `rm`.";
  rmProfile = mkProfile {
    options = [
      "--dir"
      "--force"
      "--help"
      "--interactive"
      "--no-preserve-root"
      "--one-file-system"
      "--preserve-root"
      "--presume-input-tty"
      "--recursive"
      "--verbose"
      "--version"
    ];
    optionalEquals = [
      "--interactive"
      "--preserve-root"
    ];
    conditions.recursiveForce = [
      {
        options = [ "--recursive" ];
        aliases = [
          "-r"
          "-R"
        ];
      }
      {
        options = [ "--force" ];
        aliases = [ "-f" ];
      }
    ];
  };
in
{
  features.safe-deletion = {
    name = "feature/safe-deletion";
    includes = [ features.trash ];
    agent-command-policy = [
      {
        source = "feature/safe-deletion";
        policy.commands.rm = (commandPolicy.guarded lib) rmProfile {
          guidance = trashGuidance;
          deny.recursiveForce = {
            reason = "Recursive forced deletion is disabled for coding agents.";
            alternatives = [ trashGuidance ];
          };
        };
      }
    ];
  };
}
