# Data-driven command selector grammars consumed by the shared guard.
{ lib }:
let
  executableTokenPattern = "^[a-zA-Z0-9_][a-zA-Z0-9_+@%.-]*$";
  commandTokenPattern = "^[a-zA-Z0-9_./:+@%=-]+$";
  commandOptionPattern = "^(--[a-zA-Z0-9][a-zA-Z0-9-]*|-[a-zA-Z0-9])$";
  unknownBehaviors = [
    "deny"
    "ignore"
  ];

  isUnique = values: builtins.length values == builtins.length (lib.unique values);
  hasOnlyAttrs = allowed: value: lib.all (name: lib.elem name allowed) (builtins.attrNames value);
  isCommandOption = value: builtins.match commandOptionPattern value != null;
  isCommandToken = value: builtins.isString value && builtins.match commandTokenPattern value != null;

  validAliases =
    selector: aliases:
    builtins.isAttrs aliases
    && aliases != { }
    && lib.all (
      alias:
      (
        if selector == "option" then
          isCommandOption alias
        else
          isCommandToken alias && !lib.hasPrefix "-" alias
      )
      && isCommandToken aliases.${alias}
      && !lib.hasPrefix "-" aliases.${alias}
    ) (builtins.attrNames aliases);

  validStage =
    stage:
    builtins.isAttrs stage
    && hasOnlyAttrs [
      "aliases"
      "at"
      "selector"
      "unknownOption"
      "unknownSelector"
    ] stage
    && builtins.isList (stage.at or null)
    && lib.all isCommandToken stage.at
    && lib.elem (stage.selector or null) [
      "option"
      "positional"
    ]
    && validAliases stage.selector (stage.aliases or null)
    && lib.elem (stage.unknownOption or null) unknownBehaviors
    && lib.elem (stage.unknownSelector or null) unknownBehaviors;

  validGrammar =
    grammar:
    let
      executableAliases = grammar.executableAliases or { };
      options = grammar.options or null;
      stages = grammar.stages or null;
      terminalOptions = grammar.terminalOptions or null;
      stagePaths = map (stage: builtins.toJSON stage.at) stages;
      selectorOptions = lib.concatMap (
        stage: lib.optionals (stage.selector == "option") (builtins.attrNames stage.aliases)
      ) stages;
      stageAt = path: lib.findFirst (stage: stage.at == path) null stages;
      isReachable =
        stage:
        stage.at == [ ]
        || (
          let
            parent = stageAt (lib.init stage.at);
          in
          parent != null && lib.elem (lib.last stage.at) (builtins.attrValues parent.aliases)
        );
    in
    builtins.isAttrs grammar
    && hasOnlyAttrs [
      "executableAliases"
      "options"
      "stages"
      "terminalOptions"
    ] grammar
    && builtins.isAttrs executableAliases
    && lib.all (
      alias:
      builtins.match "^[^[:space:]]+$" alias != null
      && builtins.match executableTokenPattern executableAliases.${alias} != null
    ) (builtins.attrNames executableAliases)
    && builtins.isAttrs options
    && lib.all (
      name:
      isCommandOption name
      && builtins.isInt options.${name}
      && options.${name} >= 0
      && options.${name} <= 8
    ) (builtins.attrNames options)
    && builtins.isList terminalOptions
    && lib.all isCommandOption terminalOptions
    && isUnique terminalOptions
    && builtins.isList stages
    && lib.all validStage stages
    && lib.all isReachable stages
    && isUnique stagePaths
    && (stages == [ ] || lib.elem (builtins.toJSON [ ]) stagePaths)
    && isUnique ((builtins.attrNames options) ++ terminalOptions)
    && lib.all (
      option: !(builtins.hasAttr option options) && !(builtins.elem option terminalOptions)
    ) selectorOptions;
in
{
  validate =
    grammars:
    assert lib.assertMsg (builtins.isAttrs grammars)
      "agentCommandPolicy.commandGrammars must be an attribute set";
    assert lib.assertMsg (lib.all
      (
        executable:
        builtins.match executableTokenPattern executable != null && validGrammar grammars.${executable}
      )
      (builtins.attrNames grammars)
    ) "agentCommandPolicy.commandGrammars contains an invalid command grammar";
    grammars;
}
