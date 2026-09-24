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
  base = inputs.self.homeConfigurations."constantan@linux-x86_64";
  observe =
    home:
    let
      config = home.config;
    in
    {
      integration = if config.dotfiles.agentIntegrations.hcom == null then "absent" else "present";
      skill = config.home.file ? ".agents/skills/hcom-agent-messaging";
      claudeSettings = toString config.home.file.".claude/settings.json".source;
      codexHooks = toString config.home.file.".codex/hooks.json".source;
    };
  plain = observe (
    base.extendModules { modules = [ { dotfiles.hcom.enable = lib.mkForce false; } ]; }
  );
  hcom = observe (base.extendModules { modules = [ { dotfiles.hcom.enable = lib.mkForce true; } ]; });
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
      testHcomOptionControlsAllObservableArtifacts = {
        expr = {
          plain = removeAttrs plain [
            "claudeSettings"
            "codexHooks"
          ];
          hcom = removeAttrs hcom [
            "claudeSettings"
            "codexHooks"
          ];
          consumers = {
            claudeSettingsDiffer = plain.claudeSettings != hcom.claudeSettings;
            codexHooksDiffer = plain.codexHooks != hcom.codexHooks;
          };
        };
        expected = {
          plain = {
            integration = "absent";
            skill = false;
          };
          hcom = {
            integration = "present";
            skill = true;
          };
          consumers = {
            claudeSettingsDiffer = true;
            codexHooksDiffer = true;
          };
        };
      };
      testWslProfileSelectsHunkWslRuntime = {
        expr = wsl.config.programs.hunk.package == wsl.pkgs.dotfilesPackages.hunk.wslRuntime;
        expected = true;
      };
    };
    failureCases = { };
  }
