{ inputs, ... }:
{
  imports = [
    inputs.flake-file.flakeModules.dendritic
    inputs.den.flakeModules.dendritic
    (inputs.den.namespace "features" false)

    # https://github.com/denful/den/issues/632
    # A fixed Den revision must make strictRejectsValidAspectClassIssue632 in
    # modules/_tests/den-capabilities.suite.nix stop reproducing the rejection. Turn
    # that fixture into a positive contract before importing strict here.
  ];
}
