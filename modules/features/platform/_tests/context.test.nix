{ lib }:
let
  platformContext = (import ../context.nix { inherit lib; }).features;
  profileOwner = environment: {
    dotfiles = {
      inherit environment;
      source = "/tmp/dotfiles";
    };
  };
  assertionsSucceed = assertions: builtins.all (assertion: assertion.assertion) assertions;
in
{
  testMatchingEnvironmentProfilesAreAccepted = {
    expr = [
      (assertionsSucceed
        (platformContext.platform-context-darwin-host.homeManager {
          host = profileOwner "darwin";
        }).assertions
      )
      (assertionsSucceed
        (platformContext.platform-context-linux-home.homeManager {
          home = profileOwner "linux";
        }).assertions
      )
      (assertionsSucceed
        (platformContext.platform-context-wsl-host.nixos {
          host = profileOwner "wsl";
        }).assertions
      )
    ];
    expected = [
      true
      true
      true
    ];
  };
}
