{ pkgs }:
{
  owner = "bee package smoke";
  artifacts = [
    {
      name = "bee";
      path = pkgs.dotfilesPackages.bee;
    }
  ];
  buildEntries = { };
}
