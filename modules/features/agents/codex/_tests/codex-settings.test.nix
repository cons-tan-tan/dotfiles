{ flake, lib }:
let
  home = flake.homeConfigurations."constantan@linux-x86_64".config;
  trashDirectory = "${home.xdg.dataHome}/Trash";
  settings = (import ../_lib/merge-payload.nix) {
    codexHome = "/home/test/.codex";
    settings = home.dotfiles.codex.settings;
  };
  namedSkillRules = builtins.filter (entry: entry ? name) settings.skills.config;
  disabledSkillNames = map (entry: entry.name) namedSkillRules;
in
{
  testCodexDefaultModelAndReasoning = {
    expr = {
      inherit (settings) model model_reasoning_effort;
    };
    expected = {
      model = "gpt-6.1-sol";
      model_reasoning_effort = "xhigh";
    };
  };

  testHerdrSkillIsNotDisabledByManagedConfig = {
    expr = builtins.filter (
      entry:
      (entry.path or null) == "${home.home.homeDirectory}/.codex/skills/herdr/SKILL.md"
      || (entry.name or null) == "herdr"
    ) settings.skills.config;
    expected = [ ];
  };

  testDisabledPluginSkillRulesUseUniqueQualifiedNames = {
    expr = {
      unique = builtins.length disabledSkillNames == builtins.length (lib.unique disabledSkillNames);
      qualified = builtins.all (name: builtins.match "[^:]+:[^:]+" name != null) disabledSkillNames;
      nameOnly = builtins.all (entry: !(entry ? path)) namedSkillRules;
      disabled = builtins.all (entry: entry.enabled == false) namedSkillRules;
    };
    expected = {
      unique = true;
      qualified = true;
      nameOnly = true;
      disabled = true;
    };
  };

  testDefaultPluginGroupsAreDisabled = {
    expr = lib.sort builtins.lessThan (
      lib.unique (map (name: builtins.head (lib.splitString ":" name)) disabledSkillNames)
    );
    expected = [
      "openai-templates"
      "pages"
      "plugin-management"
      "work-pets"
    ];
  };

  testUsefulSystemSkillsAreNotDisabled = {
    expr = builtins.filter (
      entry:
      builtins.any
        (
          name:
          (entry.name or null) == name
          || (entry.path or null) == "${home.home.homeDirectory}/.codex/skills/.system/${name}/SKILL.md"
        )
        [
          "imagegen"
          "openai-docs"
          "skill-creator"
        ]
    ) settings.skills.config;
    expected = [ ];
  };

  testManagedHookTrustStateIsAlwaysReplaced = {
    expr = settings.__delete_prefixes;
    expected = [
      {
        path = [
          "hooks"
          "state"
        ];
        prefix = "/home/test/.codex/hooks.json:";
      }
    ];
  };

  testTrashIsWritableWithoutOpeningTheWholeDataDirectory = {
    expr = {
      trash = settings.permissions.local-dev.filesystem.${trashDirectory};
      dataDirectory = builtins.hasAttr home.xdg.dataHome settings.permissions.local-dev.filesystem;
    };
    expected = {
      trash = "write";
      dataDirectory = false;
    };
  };
}
