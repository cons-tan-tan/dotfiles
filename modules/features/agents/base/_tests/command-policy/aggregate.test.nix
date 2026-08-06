{ lib }:
let
  aggregate = import ../../_lib/command-policy/aggregate.nix { inherit lib; };
  result = aggregate [
    {
      owner = "feature/alpha";
      policy.commands.alpha = true;
    }
    {
      owner = "feature/beta";
      policy = {
        commands.beta = false;
        shell.redirection.emptyFile = false;
      };
    }
  ];
  repeated = aggregate [
    {
      owner = "feature/repeated";
      policy.commands.repeated = true;
    }
    {
      owner = "feature/repeated";
      policy.commands.repeated = true;
    }
  ];
in
{
  testIdenticalContributionReachedThroughMultiplePathsIsIdempotent = {
    expr = {
      inherit (repeated) owners;
      moduleCount = builtins.length repeated.modules;
    };
    expected = {
      owners = [ "feature/repeated" ];
      moduleCount = 1;
    };
  };

  testContributionsBecomeOwnerAttributedModules = {
    expr = {
      inherit (result) owners;
      files = map (module: module._file) result.modules;
      policies = map (module: module.config.agentCommandPolicy) result.modules;
    };
    expected = {
      owners = [
        "feature/alpha"
        "feature/beta"
      ];
      files = [
        "agent command policy contribution from feature/alpha"
        "agent command policy contribution from feature/beta"
      ];
      policies = [
        { commands.alpha = true; }
        {
          commands.beta = false;
          shell.redirection.emptyFile = false;
        }
      ];
    };
  };
}
