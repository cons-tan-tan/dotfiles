{ lib, pkgs }:
let
  package = pkgs.callPackage ./deploy-package.nix { };
  mkActivation =
    {
      after,
      name,
      root,
      resources,
    }:
    let
      manifest = pkgs.writeText "windows-${name}-deploy.json" (
        builtins.toJSON {
          inherit root;
          directories = lib.concatMap (resource: resource.directories) resources;
          files = lib.concatMap (resource: resource.files) resources;
          trees = lib.concatMap (resource: resource.trees) resources;
        }
      );
    in
    lib.hm.dag.entryAfter after ''
      run ${lib.getExe package} ${lib.escapeShellArg manifest}
    '';
in
{
  inherit mkActivation package;
}
