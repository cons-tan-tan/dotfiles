{ lib }:
let
  deploy = import ../_interface/deploy.nix {
    inherit lib;
    pkgs = { };
  };
  resource =
    {
      files ? [ ],
      trees ? [ ],
    }:
    {
      directories = [ ];
      inherit files trees;
    };
  file = destination: { inherit destination; };
  tree = destination: { inherit destination; };
in
{
  testDistinctOwnerDestinationsAreAccepted = {
    expr = builtins.deepSeq (deploy.validateResources {
      claude = resource { trees = [ (tree ".claude/commands") ]; };
      guidance = resource { files = [ (file ".claude/CLAUDE.md") ]; };
    }) true;
    expected = true;
  };
}
