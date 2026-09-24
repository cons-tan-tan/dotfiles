{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../../../../..,
}:
let
  mkHome = import ../../../checks/_lib/eval/home-fixture.nix { inherit inputs lib repoRoot; };
  homeFor =
    producers:
    (mkHome {
      files = [
        "platform/context.nix"
        "windows/options.nix"
        "agents/skills/options.nix"
        "agents/skills/default.nix"
      ];
      modules =
        hm:
        [
          hm.platform-context
          hm.home-base
          hm.agent-skills-consumer
          {
            dotfiles.platform = {
              environment = "linux";
              source = "/source/test";
              standalone = true;
            };
          }
        ]
        ++ producers;
    }).config;
  external = {
    key = "fixture/external";
    dotfiles.agentSkillContributions = [
      {
        name = "external";
        definition.root = repoRoot + "/agents/skills/missing-tools";
        provenance = "external";
      }
    ];
  };
  local = { pkgs, ... }: {
    dotfiles.agentSkillContributions = [
      {
        name = "local";
        provenance = "local";
        definition.root = "${pkgs.writeTextDir "SKILL.md" ''
          ---
          name: local
          description: Generated skill.
          ---
          body
        ''}";
      }
    ];
  };
  # A diamond import must contribute once, just as two features may share a skill.
  tux = homeFor [
    { imports = [ external ]; }
    {
      imports = [
        external
        local
      ];
    }
  ];
  pingu = homeFor [ ];
in
if caseName != null then
  throw "agent-skills-dataflow has no failure cases"
else
  {
    meta = {
      checkName = "agent-skills-dataflow-tests";
      execution = "build";
      hestiaGroup = "eval-tests";
    };
    tests.testMergedSkillsAreRenderedAndIsolated = {
      expr = {
        tux = {
          names = builtins.attrNames tux.dotfiles.agentSkills.externalSkills;
          claude = {
            external = tux.home.file ? ".claude/skills/external";
            local = tux.home.file ? ".claude/skills/local";
          };
          agents = {
            external = tux.home.file ? ".agents/skills/external";
            local = tux.home.file ? ".agents/skills/local";
          };
          localSourceRendered =
            toString tux.home.file.".agents/skills/local".source
            != toString tux.dotfiles.agentSkills.externalSkills.local.root;
        };
        pingu = {
          names = builtins.attrNames pingu.dotfiles.agentSkills.externalSkills;
          leaked = pingu.home.file ? ".agents/skills/external";
        };
      };
      expected = {
        tux = {
          names = [
            "external"
            "local"
          ];
          claude = {
            external = true;
            local = true;
          };
          agents = {
            external = true;
            local = true;
          };
          localSourceRendered = true;
        };
        pingu = {
          names = [ ];
          leaked = false;
        };
      };
    };
    failureCases = { };
  }
