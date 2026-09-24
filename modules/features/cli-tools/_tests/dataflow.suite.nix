{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../../../..,
}:
let
  mkHome = import ../../checks/_lib/eval/home-fixture.nix { inherit inputs lib repoRoot; };
  homeFor =
    entries:
    mkHome {
      files = [
        "platform/context.nix"
        "windows/options.nix"
        "windows/base.nix"
        "cli-tools/options.nix"
        "cli-tools/default.nix"
        "cli-tools/winget.nix"
      ];
      modules = hm: [
        hm.platform-context
        hm.home-base
        hm.windows-base
        hm.cli-tools-consumer
        hm.cli-tools-winget
        {
          dotfiles.platform = {
            environment = "wsl";
            source = "/source/test";
            standalone = true;
            windows = {
              enable = true;
              username = "test-win";
              homedir = "/mnt/c/Users/test-win";
            };
          };
          dotfiles.cliTools = entries;
        }
      ];
    };
  fixture = homeFor [
    {
      id = "fixture";
      nix = {
        route = "home-packages";
        nixpkgsAttr = "reuse";
      };
      winget.packageId = "Example.Fixture";
    }
  ];
  plain = homeFor [ ];
  wingetFiles = home: home.config.dotfiles.windows.deployments.winget.files;
  wingetSource =
    home:
    (lib.findFirst (file: file.destination == ".config/dev.winget") null (wingetFiles home)).source;
in
if caseName != null then
  throw "cli-tools-dataflow has no failure cases"
else
  {
    meta = {
      checkName = "cli-tools-dataflow-tests";
      execution = "build";
      hestiaGroup = "eval-tests";
    };
    tests.testEntryReachesBothConsumersWithoutLeakingAcrossHomes = {
      expr = {
        fixtureNixPackage = builtins.elem fixture.pkgs.reuse fixture.config.home.packages;
        plainNixPackage = builtins.elem plain.pkgs.reuse plain.config.home.packages;
        wingetDestination = map (file: file.destination) (wingetFiles fixture);
        wingetSourceChanged = toString (wingetSource fixture) != toString (wingetSource plain);
      };
      expected = {
        fixtureNixPackage = true;
        plainNixPackage = false;
        wingetDestination = [ ".config/dev.winget" ];
        wingetSourceChanged = true;
      };
    };
    failureCases = { };
  }
