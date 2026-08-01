# command固有のoption grammarと、policyから参照するnamed condition。
{ lib }:
let
  flattenAliases = lib.concatLists;

  optionPrefixes =
    option:
    map (length: builtins.substring 0 length option) (lib.range 3 (builtins.stringLength option));

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
in
{
  inherit mkAbbreviatedLongOptionProfile;

  rm = mkAbbreviatedLongOptionProfile {
    options = [
      "--dir"
      "--force"
      "--help"
      "--interactive"
      "--no-preserve-root"
      "--one-file-system"
      "--preserve-root"
      "--presume-input-tty"
      "--recursive"
      "--verbose"
      "--version"
    ];
    optionalEquals = [
      "--interactive"
      "--preserve-root"
    ];
    conditions.recursiveForce = [
      {
        options = [ "--recursive" ];
        aliases = [
          "-r"
          "-R"
        ];
      }
      {
        options = [ "--force" ];
        aliases = [ "-f" ];
      }
    ];
  };

  # Full option arity prevents a value such as `-x` from being mistaken for
  # an execution option (`fd -E -x` is an exclude pattern, not command execution).
  fd = {
    optionSyntax = {
      valueTaking = flattenAliases [
        [ "--and" ]
        [
          "-d"
          "--max-depth"
        ]
        [ "--min-depth" ]
        [ "--exact-depth" ]
        [
          "-E"
          "--exclude"
        ]
        [
          "-t"
          "--type"
        ]
        [
          "-e"
          "--extension"
        ]
        [
          "-S"
          "--size"
        ]
        [ "--changed-within" ]
        [
          "--change-newer-than"
          "--newer"
        ]
        [ "--changed-after" ]
        [ "--changed-before" ]
        [
          "--change-older-than"
          "--older"
        ]
        [
          "-o"
          "--owner"
        ]
        [ "--format" ]
        [ "--batch-size" ]
        [ "--ignore-file" ]
        [
          "-c"
          "--color"
        ]
        [ "--ignore-contain" ]
        [
          "-j"
          "--threads"
        ]
        [ "--max-results" ]
        [
          "-C"
          "--base-directory"
        ]
        [ "--path-separator" ]
        [ "--search-path" ]
      ];
      optionalEquals = [
        "--hyperlink"
        "--strip-cwd-prefix"
      ];
    };
    conditions.execution = [
      [
        "-x"
        "-X"
        "--exec"
        "--exec-batch"
      ]
    ];
  };

  # Python argparse accepts every unambiguous long-option prefix. Generate
  # those aliases from the canonical option set instead of maintaining them by hand.
  trashRestore = mkAbbreviatedLongOptionProfile {
    options = [
      "--help"
      "--overwrite"
      "--print-completion"
      "--sort"
      "--trash-dir"
      "--version"
    ];
    valueTaking = [
      "--print-completion"
      "--sort"
      "--trash-dir"
    ];
    conditions.overwrite = [ { options = [ "--overwrite" ]; } ];
  };
}
