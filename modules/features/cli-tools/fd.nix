{
  lib,
  ...
}:
let
  flattenAliases = lib.concatLists;
  # The decoder needs exact arities to find every `;`-delimited exec boundary.
  # Keep this allowlist aligned with the packaged fd; unknown options fail closed.
  flagOptions = flattenAliases [
    [
      "-H"
      "--hidden"
    ]
    [ "--no-hidden" ]
    [
      "-I"
      "--no-ignore"
    ]
    [ "--ignore" ]
    [ "--no-ignore-vcs" ]
    [ "--ignore-vcs" ]
    [ "--no-require-git" ]
    [ "--require-git" ]
    [ "--no-ignore-parent" ]
    [ "--no-global-ignore-file" ]
    [
      "-u"
      "--unrestricted"
    ]
    [
      "-s"
      "--case-sensitive"
    ]
    [
      "-i"
      "--ignore-case"
    ]
    [
      "-g"
      "--glob"
    ]
    [ "--regex" ]
    [
      "-F"
      "--fixed-strings"
    ]
    [ "--literal" ]
    [
      "-a"
      "--absolute-path"
    ]
    [ "--relative-path" ]
    [
      "-l"
      "--list-details"
    ]
    [
      "-L"
      "--follow"
    ]
    [ "--dereference" ]
    [ "--no-follow" ]
    [
      "-p"
      "--full-path"
    ]
    [
      "-0"
      "--print0"
    ]
    [ "--prune" ]
    [ "--hyperlink" ]
    [ "--hyper" ]
    [ "--strip-cwd-prefix" ]
    [ "--show-errors" ]
    [ "--one-file-system" ]
    [ "--mount" ]
    [ "--xdev" ]
    [ "-1" ]
    [
      "-q"
      "--quiet"
    ]
    [ "--has-results" ]
  ];
  valueTakingOptions = flattenAliases [
    [ "--and" ]
    [
      "-d"
      "--max-depth"
      "--maxdepth"
    ]
    [
      "--min-depth"
      "--mindepth"
    ]
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
    [ "--max-buffer-time" ]
  ];
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
          policy = {
            commandGrammars.fd = {
              options = lib.genAttrs flagOptions (_: 0) // lib.genAttrs valueTakingOptions (_: 1);
              terminalOptions = [
                "-h"
                "--help"
                "-V"
                "--version"
                "--gen-completions"
              ];
              stages = [ ];
            };
            commands.fd = true;
          };
        }
      ];
    };
}
