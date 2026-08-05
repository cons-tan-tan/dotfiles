{ lib, pkgs }:
let
  package = pkgs.callPackage ../_packages/companion-deploy { };
  validateResources =
    resources:
    let
      claims = lib.concatLists (
        lib.mapAttrsToList (
          owner: resource:
          map (file: {
            destination = file.destination;
            kind = "file";
            inherit owner;
          }) (resource.files or [ ])
          ++ map (tree: {
            destination = tree.destination;
            kind = "tree";
            inherit owner;
          }) (resource.trees or [ ])
        ) resources
      );
      indexedClaims = lib.imap0 (index: claim: claim // { inherit index; }) claims;
      overlaps =
        left: right: left == right || lib.hasPrefix "${left}/" right || lib.hasPrefix "${right}/" left;
      collisions = lib.concatMap (
        left:
        map
          (right: {
            left = removeAttrs left [ "index" ];
            right = removeAttrs right [ "index" ];
          })
          (
            builtins.filter (
              right: left.index < right.index && overlaps left.destination right.destination
            ) indexedClaims
          )
      ) indexedClaims;
    in
    if collisions != [ ] then
      throw "Windows companion resource destinations have multiple owners: ${builtins.toJSON collisions}"
    else
      resources;
  mkActivation =
    {
      after,
      name,
      root,
      resources,
    }:
    let
      validatedResources = validateResources resources;
      resourceValues = builtins.attrValues validatedResources;
      manifest = pkgs.writeText "windows-${name}-deploy.json" (
        builtins.toJSON {
          inherit root;
          directories = lib.concatMap (resource: resource.directories) resourceValues;
          files = lib.concatMap (resource: resource.files) resourceValues;
          trees = lib.concatMap (resource: resource.trees) resourceValues;
        }
      );
    in
    lib.hm.dag.entryAfter after ''
      run ${lib.getExe package} ${lib.escapeShellArg manifest}
    '';
in
{
  inherit mkActivation package validateResources;
}
