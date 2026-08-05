{
  lib,
  ...
}:
let
  commandPolicy = import ../agents/base/_interface/command-policy.nix;
  mkProfile = commandPolicy.mkAbbreviatedLongOptionProfile lib;
  guarded = commandPolicy.guarded lib;
  trashRestoreProfile = mkProfile {
    options = [
      "--help"
      "--overwrite"
      "--print-completion"
      "--sort"
      "--trash-dir"
      "--version"
    ];
    valueTaking = [
      "--print-completion"
      "--sort"
      "--trash-dir"
    ];
    conditions.overwrite = [ { options = [ "--overwrite" ]; } ];
  };
in
{
  features.trash.agent-command-policy = [
    {
      source = "feature/trash";
      policy.commands = {
        trash = true;
        trash-put = true;
        trash-list = true;
        trash-empty = false;
        trash-rm = false;
        trash-restore = guarded trashRestoreProfile {
          deny.overwrite = {
            reason = "Overwriting an existing path during trash restore is disabled for coding agents.";
            alternatives = [ "Restore only when the original path does not exist." ];
          };
        };
      };
    }
  ];
}
