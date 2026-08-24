{
  caseName ? null,
  inputs,
  lib,
  ...
}:
let
  meta = {
    checkName = "den-unfree-capability-tests";
    execution = "evaluation-complete";
    hestiaGroup = null;
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
                system.stateVersion = "25.11";
              };
              den.default.homeManager.home.stateVersion = "25.11";
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

  fixtureOverlay =
    final: _prev:
    let
      mkFixture =
        pname:
        final.stdenvNoCC.mkDerivation {
          inherit pname;
          version = "1";
          dontUnpack = true;
          installPhase = ''mkdir -p "$out"'';
          meta.license = lib.licenses.unfree;
        };
    in
    {
      den-allowed-fixture = mkFixture "den-allowed-fixture";
      den-denied-fixture = mkFixture "den-denied-fixture";
    };
  probeModule =
    { pkgs, lib, ... }:
    {
      options.denUnfreeProbe = lib.mkOption {
        type = lib.types.attrsOf lib.types.bool;
      };
      config.denUnfreeProbe = {
        allowed = (builtins.tryEval pkgs.den-allowed-fixture.drvPath).success;
        denied = (builtins.tryEval pkgs.den-denied-fixture.drvPath).success;
      };
    };
  fixturePackages =
    { class, ... }:
    {
      name = "unfree-fixture-packages";
      ${class} = {
        imports = [ probeModule ];
        nixpkgs.overlays = [ fixtureOverlay ];
      };
    };
  fixtureProbe =
    { class, ... }:
    {
      name = "unfree-fixture-probe";
      ${class}.imports = [ probeModule ];
    };
  expectedProbe = {
    allowed = true;
    denied = false;
  };
  tests = {
    testIntegratedHomeManagerUsesHostPredicate = evalTest (
      {
        den,
        igloo,
        tuxHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users.tux.classes = [ "homeManager" ];
        den.aspects.igloo = {
          includes = [ fixturePackages ];
          nixos.home-manager.useGlobalPkgs = true;
        };
        den.aspects.tux.includes = [
          den.batteries.define-user
          fixtureProbe
          (den.batteries.unfree [ "den-allowed-fixture" ])
        ];

        expr = {
          host = igloo.denUnfreeProbe;
          home = tuxHm.denUnfreeProbe;
        };
        expected = {
          host = expectedProbe;
          home = expectedProbe;
        };
      }
    );

    testStandaloneHomeManagerUsesOwnPredicate = evalTest (
      { den, config, ... }:
      {
        den.homes.x86_64-linux."tux@standalone".aspect = den.aspects.standalone;
        den.aspects.standalone.includes = [
          den.batteries.define-user
          fixturePackages
          (den.batteries.unfree [ "den-allowed-fixture" ])
        ];

        expr = config.flake.homeConfigurations."tux@standalone".config.denUnfreeProbe;
        expected = expectedProbe;
      }
    );
  };
  failureCases = { };
in
if caseName == null then
  {
    inherit failureCases meta tests;
  }
else
  throw "den-unfree-capability has no failure cases"
