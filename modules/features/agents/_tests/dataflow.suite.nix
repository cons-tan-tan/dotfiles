{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../../../..,
}:
let
  mkHome = import ../../checks/_lib/eval/home-fixture.nix { inherit inputs lib repoRoot; };
  policyHome =
    producers:
    (mkHome {
      files = [
        "agents/base/default.nix"
        "agents/base/options.nix"
      ];
      modules = hm: [ hm.agents-base ] ++ producers;
    }).config.dotfiles.agentCommandPolicy.commands;
  tux = policyHome [
    {
      dotfiles.agentCommandPolicyContributions = [
        {
          owner = "alpha";
          policy.commands.alpha = true;
        }
      ];
    }
    {
      dotfiles.agentCommandPolicyContributions = [
        {
          owner = "beta";
          policy.commands.beta = false;
        }
      ];
    }
  ];
  pingu = policyHome [ { agentCommandPolicy.commands.pingu = true; } ];
  wsl = inputs.self.homeConfigurations."constantan@wsl-x86_64";
in
if caseName != null then
  throw "agent-dataflow has no failure cases"
else
  {
    meta = {
      checkName = "agent-dataflow-tests";
      execution = "build";
      hestiaGroup = "eval-tests";
    };
    tests = {
      testCommandPolicyMergesProducersAndKeepsHomesIsolated = {
        expr = {
          tux = {
            inherit (tux) alpha beta;
            pingu = tux.pingu or null;
          };
          pingu = {
            inherit (pingu) pingu;
            alpha = pingu.alpha or null;
          };
        };
        expected = {
          tux = {
            alpha = true;
            beta = false;
            pingu = null;
          };
          pingu = {
            pingu = true;
            alpha = null;
          };
        };
      };
      testWslProfileUsesDefaultHunkPackage = {
        expr = wsl.config.programs.hunk.package == wsl.pkgs.dotfilesPackages.hunk.package;
        expected = true;
      };
    };
    failureCases = { };
  }
