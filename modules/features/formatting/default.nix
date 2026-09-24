{
  inputs,
  lib,
  ...
}:
let
  ciCheck = import ../ci/_interface/check.nix { inherit lib; };
  appsFor =
    { pkgs, self', ... }:
    import ./_interface/app-set.nix {
      formatter = self'.formatter;
      inherit pkgs;
    };
  checkProducer =
    { config, ... }:
    ciCheck.mkBuildProducer {
      owner = "formatting checks";
      entries.treefmt = ciCheck.buildEntry (ciCheck.targets.linux "repo-quality") (
        config.treefmt.build.check config.treefmt.projectRoot
      );
    };
in
{
  flake-file.inputs.treefmt-nix = {
    url = "github:numtide/treefmt-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  imports = [
    inputs.treefmt-nix.flakeModule
    ../ci/_interface/options.nix
  ];

  perSystem =
    {
      pkgs,
      config,
      self',
      ...
    }:
    let
      appSet = appsFor { inherit pkgs self'; };
      producer = checkProducer { inherit config; };
    in
    {
      treefmt = {
        flakeCheck = false;
        projectRootFile = "flake.nix";
        programs = {
          nixf-diagnose = {
            enable = true;
            autoFix = true;
          };
          nixfmt.enable = true;
          rustfmt.enable = true;
          shfmt.enable = true;
        };
        settings = {
          formatter.nixf-diagnose.priority = -1;
          global.excludes = [
            ".direnv/**"
            ".git/**"
            "*.lock"
            "result"
          ];
        };
      };
      inherit (appSet) apps;
      dotfiles.appValidationSets = [ appSet.validationsByName ];
      checks = producer.checks;
      dotfiles.ci.buildRouteProducers = [ { inherit (producer) owner routes; } ];
    };
}
