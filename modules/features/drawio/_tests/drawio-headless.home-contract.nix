{ lib }:
{
  describe =
    target:
    let
      package = lib.attrByPath [
        "dotfilesPackages"
        "drawio-headless"
      ] null target.pkgs;
    in
    {
      delivered = package != null && lib.elem package target.config.home.packages;
    };
  expected = facts: {
    delivered = facts.environment != "darwin";
  };
}
