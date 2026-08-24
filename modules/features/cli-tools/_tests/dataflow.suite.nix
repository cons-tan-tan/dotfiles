{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../../../..,
}:
let
  meta = {
    checkName = "cli-tools-dataflow-tests";
    execution = "build";
    hestiaGroup = "eval-tests";
  };
  testImports = lib.optional (inputs ? flake-parts) inputs.den.flakeOutputs.flake ++ [
    (inputs.den.namespace "features" false)
    {
      options.flake-file = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
    }
    (repoRoot + "/modules/features/windows/class.nix")
    (repoRoot + "/modules/features/cli-tools/quirk.nix")
  ];

  evalTest =
    module:
    (lib.evalModules {
      specialArgs = { inherit inputs; };
      modules = [
        inputs.den.flakeModules.denTest
        { denTest.imports = testImports; }
        (
          { denTest, ... }:
          {
            options.result = lib.mkOption { type = lib.types.raw; };
            config.result = denTest module;
          }
        )
      ];
    }).config.result;

  baseHome =
    { lib, ... }:
    {
      den.default.homeManager.home = {
        username = lib.mkDefault "test";
        homeDirectory = lib.mkDefault "/home/test";
        stateVersion = "25.11";
      };
    };

  tests = {
    testSyntheticEntryReachesNixAndWingetConsumers = evalTest (
      {
        config,
        features,
        ...
      }:
      let
        homeFor = name: config.flake.homeConfigurations.${name};
        wingetSourceFor =
          name:
          let
            files = (homeFor name).config.dotfiles.windows.deployments.winget.files;
            file = lib.findFirst (candidate: candidate.destination == ".config/dev.winget") null files;
          in
          if file == null then null else file.source;
        mkAspect = name: {
          includes = [
            features.platform-context
            features.windows-base
            features.cli-tools-consumer
            features.cli-tools-winget
          ];
          homeManager = {
            home = {
              username = lib.mkForce name;
              homeDirectory = lib.mkForce "/home/${name}";
            };
            dotfiles.platform = {
              environment = "wsl";
              source = "/source/${name}";
              standalone = true;
              windows = {
                enable = true;
                username = "${name}-win";
                homedir = "/mnt/c/Users/${name}-win";
              };
            };
          };
        };
      in
      {
        imports = [
          baseHome
          (repoRoot + "/modules/features/platform/context.nix")
          (repoRoot + "/modules/features/windows/base.nix")
          (repoRoot + "/modules/features/cli-tools/default.nix")
          (repoRoot + "/modules/features/cli-tools/winget.nix")
        ];
        den.homes.x86_64-linux = {
          fixture = { };
          plain = { };
        };
        den.aspects.plain = mkAspect "plain";
        den.aspects.fixture = (mkAspect "fixture") // {
          cli-tools = [
            {
              id = "fixture";
              nix = {
                route = "home-packages";
                nixpkgsAttr = "reuse";
              };
              winget.packageId = "Example.Fixture";
            }
          ];
        };

        expr = {
          fixtureNixPackage = builtins.elem (homeFor "fixture").pkgs.reuse (homeFor "fixture")
          .config.home.packages;
          plainNixPackage = builtins.elem (homeFor "plain").pkgs.reuse (homeFor "plain").config.home.packages;
          wingetDestination =
            map (file: file.destination)
              (homeFor "fixture").config.dotfiles.windows.deployments.winget.files;
          wingetSourceChanged = toString (wingetSourceFor "fixture") != toString (wingetSourceFor "plain");
        };
        expected = {
          fixtureNixPackage = true;
          plainNixPackage = false;
          wingetDestination = [ ".config/dev.winget" ];
          wingetSourceChanged = true;
        };
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
  failureCases.${caseName}.expression
