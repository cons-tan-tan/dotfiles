{ lib }:
let
  aggregate = import ../../_lib/command-policy/aggregate.nix { inherit lib; };
  result = aggregate [
    {
      source = "feature/alpha";
      policy.commands.alpha = true;
    }
    {
      source = "feature/beta";
      policy = {
        commands.beta = false;
        shell.redirection.emptyFile = false;
      };
    }
  ];
  repeated = aggregate [
    {
      source = "feature/repeated";
      policy.commands.repeated = true;
    }
    {
      source = "feature/repeated";
      policy.commands.repeated = true;
    }
  ];
in
{
  testIdenticalContributionReachedThroughMultiplePathsIsIdempotent = {
    expr = {
      inherit (repeated) sources;
      moduleCount = builtins.length repeated.modules;
    };
    expected = {
      sources = [ "feature/repeated" ];
      moduleCount = 1;
    };
  };

  testContributionsBecomeSourceAttributedModules = {
    expr = {
      inherit (result) sources;
      files = map (module: module._file) result.modules;
      policies = map (module: module.config.agentCommandPolicy) result.modules;
    };
    expected = {
      sources = [
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
