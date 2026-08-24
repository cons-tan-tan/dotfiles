{
  caseName ? null,
  inputs,
  lib,
  ...
}:
let
  meta = {
    checkName = "den-capability-tests";
    execution = "build";
    hestiaGroup = "eval-tests";
  };

  evalTest =
    module:
    (lib.evalModules {
      specialArgs = { inherit inputs; };
      modules = [
        inputs.den.flakeModules.denTest
        {
          denTest.imports = [
            inputs.den.flakeOutputs.flake
            {
              den.default.nixos = {
                boot.loader.grub.enable = false;
                fileSystems."/" = {
                  device = "/dev/fake";
                  fsType = "auto";
                };
              };
            }
          ];
        }
        (
          { denTest, ... }:
          {
            options.result = lib.mkOption { type = lib.types.raw; };
            config.result = denTest module;
          }
        )
      ];
    }).config.result;

  tests = {
    testAspectClassIsAcceptedWithoutStrictMode = evalTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.probe.nixos.environment.etc."den-class-probe".text = "accepted";
        den.aspects.igloo.includes = [ den.aspects.probe ];

        expr = igloo.environment.etc."den-class-probe".text or "dropped";
        expected = "accepted";
      }
    );
  };

  failureCases = {
    # This is the repository's removal sentinel for the temporary strict-mode
    # workaround in modules/dendritic.nix and modules/schema/entities.nix.
    strictRejectsValidAspectClassIssue632 = {
      expression =
        let
          evaluated = lib.evalModules {
            specialArgs = { inherit inputs; };
            modules = [
              inputs.den.flakeModule
              inputs.den.flakeModules.strict
              { den.aspects.probe.nixos = { }; }
            ];
          };
        in
        builtins.deepSeq evaluated.config.den.aspects.probe true;
      expectedFragments = [
        "STRICT MODE"
        ''Attempted to set the option "nixos" in "den.aspects.probe"''
      ];
    };
  };
in
if caseName == null then
  {
    inherit failureCases meta tests;
  }
else
  failureCases.${caseName}.expression
