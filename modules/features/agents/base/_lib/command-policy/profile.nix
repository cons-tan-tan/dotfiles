{ lib }:
let
  optionPrefixes =
    option:
    map (length: builtins.substring 0 length option) (lib.range 3 (builtins.stringLength option));
in
{
  mkAbbreviatedLongOptionProfile =
    {
      options,
      valueTaking ? [ ],
      optionalEquals ? [ ],
      conditions ? { },
    }:
    let
      expandOption =
        option:
        assert lib.assertMsg (lib.elem option options)
          "abbreviated long-option profile references an unknown option: ${option}";
        builtins.filter (
          prefix:
          prefix == option
          || builtins.length (builtins.filter (candidate: lib.hasPrefix prefix candidate) options) == 1
        ) (optionPrefixes option);
      expandOptions = values: lib.unique (lib.concatMap expandOption values);
      expandConditionGroup = group: (group.aliases or [ ]) ++ expandOptions group.options;
    in
    assert lib.assertMsg (lib.all (lib.hasPrefix "--") options)
      "abbreviated long-option profiles support only canonical long options";
    assert lib.assertMsg (
      builtins.length options == builtins.length (lib.unique options)
    ) "abbreviated long-option profile options must be unique";
    {
      optionSyntax = {
        valueTaking = expandOptions valueTaking;
        optionalEquals = expandOptions optionalEquals;
      };
      conditions = builtins.mapAttrs (_: groups: map expandConditionGroup groups) conditions;
    };
}
