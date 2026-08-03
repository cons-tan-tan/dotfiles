{ inputs, ... }:
{
  imports = [
    inputs.flake-file.flakeModules.dendritic
    inputs.den.flakeModules.dendritic

    # https://github.com/denful/den/issues/632
    # Add inputs.den.flakeModules.strict here after strictModeIssue632 in
    # modules/_tests/den-capabilities.nix succeeds against a fixed revision.
  ];
}
