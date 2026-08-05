let
  discovery = ../_tests/test-discovery.test.nix;
  evaluationComplete = [
    ../_tests/dendritic-test-discovery.test.nix
    ../_tests/dendritic-module-boundary.test.nix
  ];
in
{
  all = [ discovery ] ++ evaluationComplete;
  inherit discovery evaluationComplete;
}
