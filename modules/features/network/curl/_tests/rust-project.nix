{
  ciCheck,
  pkgs,
  publicArtifacts ? [ ],
}:
let
  package = pkgs.callPackage ../_packages/safe-fetch { };
  checkPackage = pkgs.linkFarm "safe-fetch-rust" (
    [
      {
        name = "core";
        path = package.core;
      }
      {
        name = "curl-fetch";
        path = pkgs.dotfilesPackages.curl-fetch;
      }
    ]
    ++ publicArtifacts
  );
in
{
  name = "safe-fetch";
  manifest = "modules/features/network/curl/_packages/safe-fetch/Cargo.toml";
  ciTargets = ciCheck.targets.both "rust-and-bats";
  platformPredicate = _platform: true;
  advisoryOnly = false;
  lock = {
    owner = "safe-fetch";
    path = "modules/features/network/curl/_packages/safe-fetch/Cargo.lock";
    ignoredAdvisories = [ ];
  };
  packages = package // {
    check = checkPackage;
  };
  buildVariants = [
    {
      name = "default";
      checkName = "safe-fetch-rust";
      package = checkPackage;
    }
  ];
  clippyVariants = [
    {
      name = "default";
      checkName = "safe-fetch";
      package = package.core;
      clippyFlags = [
        "--all-targets"
        "--all-features"
      ];
    }
  ];
}
