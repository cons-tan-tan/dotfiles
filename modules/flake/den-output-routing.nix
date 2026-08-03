{ den, ... }:
let
  toFlakeParts = output: _: [
    (den.lib.policy.route {
      fromClass = output;
      intoClass = "flake-parts";
      collectSubtree = true;
      path = [ output ];
      adaptArgs = { config, ... }: config.allModuleArgs;
    })
  ];
in
{
  den.policies.apps-to-flake-parts = toFlakeParts "apps";
  den.policies.checks-to-flake-parts = toFlakeParts "checks";
  den.policies.devShells-to-flake-parts = toFlakeParts "devShells";

  den.schema.flake-system = {
    includes = [ den.policies.system-to-flake-parts ];
    excludes = [
      den.policies.apps-to-flake
      den.policies.checks-to-flake
      den.policies.devShells-to-flake
    ];
  };

  den.schema.flake-parts.includes = [
    den.policies.apps-to-flake-parts
    den.policies.checks-to-flake-parts
    den.policies.devShells-to-flake-parts
  ];
}
