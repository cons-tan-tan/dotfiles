{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../../../..,
}:
let
  meta = {
    checkName = "agent-den-dataflow-tests";
    execution = "build";
    hestiaGroup = "eval-tests";
  };
  agentsRoot = repoRoot + "/modules/features/agents";

  testImports = lib.optional (inputs ? flake-parts) inputs.den.flakeOutputs.flake ++ [
    (inputs.den.namespace "features" false)
    {
      options.flake-file = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
    }
    (repoRoot + "/modules/features/agents/skills/quirk.nix")
    (repoRoot + "/modules/features/agents/base/quirk.nix")
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
        username = "test";
        homeDirectory = lib.mkForce "/home/test";
        stateVersion = "25.11";
      };
    };

  tests = {
    testCommandPolicyMergesProducersAndKeepsUserScopesIsolated = evalTest (
      {
        den,
        features,
        pinguHm,
        tuxHm,
        ...
      }:
      {
        imports = [
          baseHome
          (agentsRoot + "/base/default.nix")
        ];
        den.hosts.x86_64-linux.igloo.users = {
          pingu = { };
          tux = { };
        };

        den.aspects.policy-alpha =
          { config, ... }:
          {
            name = "fixture/policy-alpha";
            agent-command-policy = [
              {
                owner = config.name;
                policy.commands.alpha = true;
              }
            ];
          };
        den.aspects.policy-beta =
          { config, ... }:
          {
            name = "fixture/policy-beta";
            agent-command-policy = [
              {
                owner = config.name;
                policy.commands.beta = false;
              }
            ];
          };
        den.aspects.tux = {
          includes = [
            features.agents-base
            den.aspects.policy-alpha
            den.aspects.policy-beta
          ];
        };
        den.aspects.pingu = {
          includes = [
            features.agents-base
          ];
          homeManager.agentCommandPolicy.commands.pingu = true;
        };

        expr = {
          tux = {
            inherit (tuxHm.dotfiles.agentCommandPolicy.commands) alpha beta;
            pingu = tuxHm.dotfiles.agentCommandPolicy.commands.pingu or null;
          };
          pingu = {
            inherit (pinguHm.dotfiles.agentCommandPolicy.commands) pingu;
            alpha = pinguHm.dotfiles.agentCommandPolicy.commands.alpha or null;
          };
        };
        expected = {
          tux = {
            alpha = true;
            beta = false;
            pingu = null;
          };
          pingu = {
            alpha = null;
            pingu = true;
          };
        };
      }
    );

    testHcomOptionControlsAllObservableArtifacts = evalTest (
      {
        config,
        features,
        ...
      }:
      let
        overlayPlan = (import (repoRoot + "/modules/features/nixpkgs/_interface")).mkOverlayPlan {
          inherit inputs;
          system = "x86_64-linux";
        };
        observe =
          name:
          let
            home = config.flake.homeConfigurations.${name}.config;
            hcom = home.dotfiles.agentIntegrations.hcom;
          in
          {
            integration = if hcom == null then "absent" else "present";
            skill = home.home.file ? ".agents/skills/hcom-agent-messaging";
            claudeSettings = toString home.home.file.".claude/settings.json".source;
            codexHooks = toString home.home.file.".codex/hooks.json".source;
          };
        plain = observe "plain";
        hcom = observe "hcom";
      in
      {
        imports = [
          baseHome
          (agentsRoot + "/default.nix")
          (agentsRoot + "/ax.nix")
          (agentsRoot + "/base/default.nix")
          (agentsRoot + "/bee/default.nix")
          (agentsRoot + "/browser/default.nix")
          (agentsRoot + "/ccusage.nix")
          (agentsRoot + "/claude/default.nix")
          (agentsRoot + "/claude/home.nix")
          (agentsRoot + "/codex/default.nix")
          (agentsRoot + "/codex/home.nix")
          (agentsRoot + "/copilot.nix")
          (agentsRoot + "/difit/default.nix")
          (agentsRoot + "/gemini.nix")
          (agentsRoot + "/guidance/default.nix")
          (agentsRoot + "/guidance/home.nix")
          (agentsRoot + "/herdr/default.nix")
          (agentsRoot + "/herdr/home.nix")
          (agentsRoot + "/hunk/default.nix")
          (agentsRoot + "/hunk/home.nix")
          (agentsRoot + "/opencode/default.nix")
          (agentsRoot + "/opencode/home.nix")
          (agentsRoot + "/pi/default.nix")
          (agentsRoot + "/pi/home.nix")
          (agentsRoot + "/skills/default.nix")
          (repoRoot + "/modules/features/pptx/default.nix")
          (repoRoot + "/modules/features/drawio/default.nix")
          (agentsRoot + "/slack/default.nix")
          (agentsRoot + "/hcom/contract.nix")
          (agentsRoot + "/hcom/default.nix")
          (repoRoot + "/modules/features/platform/context.nix")
        ];
        den.default.homeManager = {
          dotfiles.platform = {
            environment = "linux";
            source = toString repoRoot;
            standalone = true;
          };
          nixpkgs.overlays = overlayPlan.overlays;
        };
        den.homes.x86_64-linux = {
          plain = { };
          hcom = { };
        };
        den.aspects.plain.includes = [
          features.platform-context
          features.agents-default
        ];
        den.aspects.hcom = {
          includes = [
            features.platform-context
            features.agents-default
          ];
          homeManager.dotfiles.hcom.enable = true;
        };

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
      }
    );

    testHunkWslAspectSelectsWslRuntime = evalTest (
      {
        config,
        features,
        ...
      }:
      let
        overlayPlan = (import (repoRoot + "/modules/features/nixpkgs/_interface")).mkOverlayPlan {
          inherit inputs;
          system = "x86_64-linux";
        };
        home = config.flake.homeConfigurations.tux;
      in
      {
        imports = [
          baseHome
          (agentsRoot + "/hunk/default.nix")
          (agentsRoot + "/hunk/home.nix")
          (agentsRoot + "/skills/default.nix")
        ];
        den.default.homeManager.nixpkgs.overlays = overlayPlan.overlays;
        den.homes.x86_64-linux.tux = { };
        den.aspects.tux.includes = [
          features.agent-hunk
          features.agent-hunk-wsl
        ];

        expr = home.config.programs.hunk.package == home.pkgs.dotfilesPackages.hunk.wslRuntime;
        expected = true;
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
