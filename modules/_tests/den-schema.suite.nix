{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../..,
}:
let
  meta = {
    checkName = "den-schema-tests";
    execution = "build";
    hestiaGroup = "eval-tests";
  };
  schemaModule = repoRoot + "/modules/schema/entities.nix";
  evalDen =
    module:
    lib.evalModules {
      specialArgs = { inherit inputs; };
      modules = [
        inputs.den.flakeOutputs.flake
        inputs.den.flakeModule
        schemaModule
        module
      ];
    };

  enforceAssertions =
    assertions:
    let
      failure = lib.findFirst (assertion: !assertion.assertion) null assertions;
    in
    if failure == null then true else throw failure.message;

  validWindows = {
    enable = true;
    username = "windows-user";
    homedir = "/mnt/c/Users/windows-user";
  };

  tests = {
    testWslHomeAcceptsEnabledCompanion =
      let
        evaluated = evalDen {
          den.homes.x86_64-linux."test@standalone-wsl".dotfiles = {
            environment = "wsl";
            source = "/tmp/dotfiles";
            windows = validWindows;
          };
        };
      in
      {
        expr = enforceAssertions evaluated.config.den.homes.x86_64-linux."test@standalone-wsl".assertions;
        expected = true;
      };
  };

  failureCases = {
    wslHostMissingCompanion = {
      expression =
        let
          evaluated = evalDen {
            den.hosts.x86_64-linux.wsl.dotfiles = {
              environment = "wsl";
              source = "/tmp/dotfiles";
            };
          };
        in
        enforceAssertions evaluated.config.den.hosts.x86_64-linux.wsl.assertions;
      expectedFragments = [
        "dotfiles.environment = wsl requires an enabled Windows companion"
      ];
    };
    wslHomeMissingCompanion = {
      expression =
        let
          evaluated = evalDen {
            den.homes.x86_64-linux."test@standalone-wsl".dotfiles = {
              environment = "wsl";
              source = "/tmp/dotfiles";
            };
          };
        in
        enforceAssertions evaluated.config.den.homes.x86_64-linux."test@standalone-wsl".assertions;
      expectedFragments = [
        "dotfiles.environment = wsl requires an enabled Windows companion"
      ];
    };
    nonWslHostWithCompanion = {
      expression =
        let
          evaluated = evalDen {
            den.hosts.x86_64-linux.host.dotfiles = {
              environment = "linux";
              source = "/tmp/dotfiles";
              windows = validWindows;
            };
          };
        in
        enforceAssertions evaluated.config.den.hosts.x86_64-linux.host.assertions;
      expectedFragments = [ "non-WSL dotfiles.windows metadata must be disabled and empty" ];
    };
    nonWslHomeWithResidualCompanionMetadata = {
      expression =
        let
          evaluated = evalDen {
            den.homes.x86_64-linux."test@standalone-linux".dotfiles = {
              environment = "linux";
              source = "/tmp/dotfiles";
              windows = {
                username = "windows-user";
                homedir = "/mnt/c/Users/windows-user";
              };
            };
          };
        in
        enforceAssertions evaluated.config.den.homes.x86_64-linux."test@standalone-linux".assertions;
      expectedFragments = [ "non-WSL dotfiles.windows metadata must be disabled and empty" ];
    };
  };
in
if caseName == null then
  {
    inherit failureCases meta tests;
  }
else
  failureCases.${caseName}.expression
