{
  lib,
  ...
}:
let
  commandPolicy = import ../agents/base/_interface/command-policy.nix;
  flattenAliases = lib.concatLists;
  profile = {
    optionSyntax = {
      valueTaking = flattenAliases [
        [ "--and" ]
        [
          "-d"
          "--max-depth"
        ]
        [ "--min-depth" ]
        [ "--exact-depth" ]
        [
          "-E"
          "--exclude"
        ]
        [
          "-t"
          "--type"
        ]
        [
          "-e"
          "--extension"
        ]
        [
          "-S"
          "--size"
        ]
        [ "--changed-within" ]
        [
          "--change-newer-than"
          "--newer"
        ]
        [ "--changed-after" ]
        [ "--changed-before" ]
        [
          "--change-older-than"
          "--older"
        ]
        [
          "-o"
          "--owner"
        ]
        [ "--format" ]
        [ "--batch-size" ]
        [ "--ignore-file" ]
        [
          "-c"
          "--color"
        ]
        [ "--ignore-contain" ]
        [
          "-j"
          "--threads"
        ]
        [ "--max-results" ]
        [
          "-C"
          "--base-directory"
        ]
        [ "--path-separator" ]
        [ "--search-path" ]
      ];
      optionalEquals = [
        "--hyperlink"
        "--strip-cwd-prefix"
      ];
    };
    conditions.execution = [
      [
        "-x"
        "-X"
        "--exec"
        "--exec-batch"
      ]
    ];
  };
in
{
  features.cli-tool-fd =
    { config, ... }:
    {
      name = "feature/cli-tools/fd";
      cli-tools = [
        {
          id = "fd";
          nix = {
            route = "home-packages";
            nixpkgsAttr = "fd";
          };
          winget = {
            packageId = "sharkdp.fd";
            description = "fd";
          };
        }
      ];
      agent-command-policy = [
        {
          owner = config.name;
          policy.commands.fd = (commandPolicy.guarded lib) profile {
            deny.execution = {
              reason = "fd command execution options are disabled for coding agents.";
              alternatives = [
                "List matching paths first, then run a separately reviewed command."
              ];
            };
          };
        }
      ];
    };
}
