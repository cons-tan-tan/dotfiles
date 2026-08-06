{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  platformContext =
    (import (repoRoot + "/modules/features/platform/context.nix") { inherit lib; }).features;
  profileOwner = environment: {
    dotfiles = {
      inherit environment;
      source = "/tmp/dotfiles";
    };
  };
  enforceAssertions =
    assertions:
    let
      failure = lib.findFirst (assertion: !assertion.assertion) null assertions;
    in
    if failure == null then true else throw failure.message;
  cases = {
    darwinProfileRejectsLinuxOwner = {
      expression =
        enforceAssertions
          (platformContext.platform-context-darwin-host.homeManager {
            host = profileOwner "linux";
          }).assertions;
      expectedFragment = "dotfiles darwin environment aspect requires owner.dotfiles.environment = darwin";
    };
    linuxProfileRejectsWslOwner = {
      expression =
        enforceAssertions
          (platformContext.platform-context-linux-home.homeManager {
            home = profileOwner "wsl";
          }).assertions;
      expectedFragment = "dotfiles linux environment aspect requires owner.dotfiles.environment = linux";
    };
    integratedWslProfileRejectsLinuxHost = {
      expression =
        enforceAssertions
          (platformContext.platform-context-wsl-host.nixos {
            host = profileOwner "linux";
          }).assertions;
      expectedFragment = "dotfiles wsl environment aspect requires owner.dotfiles.environment = wsl";
    };
    standaloneWslProfileRejectsLinuxHome = {
      expression =
        enforceAssertions
          (platformContext.platform-context-wsl-home.homeManager {
            home = profileOwner "linux";
          }).assertions;
      expectedFragment = "dotfiles wsl environment aspect requires owner.dotfiles.environment = wsl";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
