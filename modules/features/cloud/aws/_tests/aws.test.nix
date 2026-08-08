{ lib }:
let
  fixtureLib = lib // {
    getExe = package: "${package}/bin/${baseNameOf package}";
    hm.dag.entryAfter = after: data: { inherit after data; };
  };
  fixturePkgs = {
    awscli2 = "/nix/store/aws";
    callPackage =
      path: _:
      if baseNameOf path == "config-helper" then
        "/nix/store/aws-config-helper"
      else
        "/nix/store/aws-config-reconcile";
    dotfilesPackages.aws.mkLoginPackage = _: "/nix/store/aws-login";
    writeText = name: _: "/nix/store/${name}";
  };
  module = (import ../home.nix).features.cloud-aws.homeManager {
    lib = fixtureLib;
    pkgs = fixturePkgs;
  };
  activation = module.home.activation.awsConfigMerge;
in
{
  testRunsAfterWriteBoundary = {
    expr = activation.after;
    expected = [ "writeBoundary" ];
  };

  testUsesRunForDryRunSafety = {
    expr = activation.data;
    expected = ''
      run /nix/store/aws-config-reconcile/bin/aws-config-reconcile
    '';
  };
}
