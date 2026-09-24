{
  caseName ? null,
  inputs,
  lib,
  ...
}:
let
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
      allowed-fixture = mkFixture "allowed-fixture";
      denied-fixture = mkFixture "denied-fixture";
    };
  probe = { pkgs, ... }: {
    options.unfreeProbe = lib.mkOption { type = lib.types.attrsOf lib.types.bool; };
    config.unfreeProbe = {
      allowed = (builtins.tryEval pkgs.allowed-fixture.drvPath).success;
      denied = (builtins.tryEval pkgs.denied-fixture.drvPath).success;
    };
  };
  allowance.dotfiles.unfreePackages = [ "allowed-fixture" ];
  integrated =
    configuration:
    (configuration.extendModules {
      modules = [
        probe
        {
          nixpkgs.overlays = [ fixtureOverlay ];
          home-manager.users.constantan.imports = [
            probe
            allowance
          ];
        }
      ];
    }).config;
  nixos = integrated inputs.self.nixosConfigurations.wsl;
  darwin = integrated inputs.self.darwinConfigurations.constantan;
  standalone =
    (inputs.self.homeConfigurations."constantan@linux-x86_64".extendModules {
      modules = [
        probe
        allowance
        { nixpkgs.overlays = [ fixtureOverlay ]; }
      ];
    }).config;
  expected = {
    allowed = true;
    denied = false;
  };
in
if caseName != null then
  throw "unfree-policy has no failure cases"
else
  {
    meta = {
      checkName = "unfree-policy-tests";
      execution = "evaluation-complete";
      hestiaGroup = null;
    };
    tests = {
      testNixosAndIntegratedHomeShareNarrowPredicate = {
        expr = [
          nixos.unfreeProbe
          nixos.home-manager.users.constantan.unfreeProbe
        ];
        expected = [
          expected
          expected
        ];
      };
      testDarwinAndIntegratedHomeShareNarrowPredicate = {
        expr = [
          darwin.unfreeProbe
          darwin.home-manager.users.constantan.unfreeProbe
        ];
        expected = [
          expected
          expected
        ];
      };
      testStandaloneUsesNarrowPredicate = {
        expr = standalone.unfreeProbe;
        inherit expected;
      };
    };
    failureCases = { };
  }
