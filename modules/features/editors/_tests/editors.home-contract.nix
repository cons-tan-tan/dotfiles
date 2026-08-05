{ lib }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      countPackage =
        package: builtins.length (builtins.filter (candidate: candidate == package) config.home.packages);
    in
    {
      neovim = countPackage pkgs.neovim;
      zedApp = builtins.length (
        builtins.filter (package: lib.getName package == "zed") config.home.packages
      );
      zedRuntime = countPackage pkgs.nodejs;
    };
  expected = facts: {
    neovim = 1;
    zedApp = if facts.environment == "darwin" then 1 else 0;
    zedRuntime = 1;
  };
}
