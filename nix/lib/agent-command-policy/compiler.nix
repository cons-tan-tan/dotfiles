# agent非依存のcommand policy ruleを各backendへ投影する。
{ lib, rules }:
let
  argvPrefixesFor =
    rule:
    lib.concatMap (
      command:
      lib.concatMap (
        second:
        let
          thirdTokens = rule.match.argvGroups.${command}.${second};
        in
        if thirdTokens == [ ] then
          [
            [
              command
              second
            ]
          ]
        else
          map (third: [
            command
            second
            third
          ]) thirdTokens
      ) (builtins.attrNames rule.match.argvGroups.${command})
    ) (builtins.attrNames rule.match.argvGroups)
    ++ map (command: [ command ]) rule.match.commands;

  commandOptionMatchesFor =
    rule:
    lib.concatMap (
      command: map (option: { inherit command option; }) rule.match.commandOptions.${command}
    ) (builtins.attrNames rule.match.commandOptions);

  validateRule =
    rule:
    let
      argvPrefixes = argvPrefixesFor rule;
      matcherCount = builtins.length argvPrefixes + builtins.length (commandOptionMatchesFor rule);
      emptyArgvGroups = builtins.filter (
        command: builtins.attrNames rule.match.argvGroups.${command} == [ ]
      ) (builtins.attrNames rule.match.argvGroups);
      unsafeExecutableTokens = builtins.filter (
        token: builtins.match "^[a-zA-Z0-9_][a-zA-Z0-9_+@%.-]*$" token == null
      ) (map builtins.head argvPrefixes);
      unsafeArgvTokens = builtins.filter (token: builtins.match "^[a-zA-Z0-9_./:+@%=-]+$" token == null) (
        lib.concatLists argvPrefixes
      );
      optionCommands = builtins.attrNames rule.match.commandOptions;
    in
    if matcherCount == 0 then
      throw "agent command policy rule must define at least one match expression"
    else if emptyArgvGroups != [ ] then
      throw "agent command policy rule has an empty argv group"
    else if unsafeExecutableTokens != [ ] then
      throw "agent command policy rule has invalid executable tokens"
    else if unsafeArgvTokens != [ ] then
      throw "agent command policy rule has argv tokens that cannot be projected safely"
    else if
      optionCommands != [ ]
      && !(rule.decision == "forbidden" && lib.all (command: command == "fd") optionCommands)
    then
      throw "agent command policy rule uses an unsupported command option match"
    else
      rule;

  validatedRules = map validateRule rules;
  checkedRules = builtins.deepSeq validatedRules validatedRules;

  duplicateValues =
    values:
    builtins.filter (value: builtins.length (builtins.filter (other: other == value) values) > 1) (
      lib.unique values
    );

  prefixRules = lib.concatMap (
    rule:
    map (argvPrefix: {
      inherit argvPrefix;
      inherit (rule) decision justification;
    }) (argvPrefixesFor rule)
  ) checkedRules;

  # Claudeは一部のprocess wrapperを剥がして照合するが、可変引数を持つ
  # timeout等をCodexの固定prefixで安全に一般化できないため、ここでは直接の
  # argvだけを投影する。
  # commandOptions は文字列globでは `--` 境界を保てないため、Claude/Codex
  # の両方へ導入する共通wrapperだけでargvとして検査する。
  claudePatternsFor =
    rule: map (argvPrefix: "Bash(${lib.escapeShellArgs argvPrefix} *)") (argvPrefixesFor rule);

  mkClaudePermissions =
    { }:
    let
      patternsFor =
        decision:
        lib.concatMap claudePatternsFor (builtins.filter (rule: rule.decision == decision) checkedRules);
      ask = patternsFor "prompt";
    in
    {
      allow = patternsFor "allow";
      deny = patternsFor "forbidden";
    }
    // lib.optionalAttrs (ask != [ ]) { inherit ask; };

  codexAllowedExecutables = lib.unique (
    map (rule: builtins.head rule.argvPrefix) (
      builtins.filter (rule: rule.decision == "allow") prefixRules
    )
  );
  codexForbiddenExecutables = lib.unique (
    map (rule: builtins.head rule.argvPrefix) (
      builtins.filter (rule: rule.decision == "forbidden") prefixRules
    )
  );
  mixedCodexExecutableDecisions = lib.intersectLists codexAllowedExecutables codexForbiddenExecutables;

  duplicateClaudePatterns = duplicateValues (lib.concatMap claudePatternsFor checkedRules);
  duplicateCodexPatterns = duplicateValues (map (rule: builtins.toJSON rule.argvPrefix) prefixRules);
  duplicateCommandOptionMatches = duplicateValues (
    map (
      { command, option }:
      builtins.toJSON [
        command
        option
      ]
    ) (lib.concatMap commandOptionMatchesFor checkedRules)
  );
  fdForbiddenOptions = lib.concatMap (rule: rule.match.commandOptions.fd or [ ]) checkedRules;

  mkCodexRule =
    rule:
    let
      pattern = rule.argvPrefix;
      matchProbe = lib.escapeShellArgs (pattern ++ [ "__codex_rule_probe__" ]);
      notMatchProbe = lib.escapeShellArgs ([ "__codex_rule_probe__" ] ++ pattern);
    in
    ''
      prefix_rule(
          pattern = ${builtins.toJSON pattern},
          decision = ${builtins.toJSON rule.decision},
          justification = ${builtins.toJSON rule.justification},
          match = ${builtins.toJSON [ matchProbe ]},
          not_match = ${builtins.toJSON [ notMatchProbe ]},
      )
    '';

  mkCodexHostExecutable = name: ''
    host_executable(
        name = ${builtins.toJSON name},
        paths = [],
    )
  '';

  codexRulesContent = ''
    # Generated from nix/lib/agent-command-policy/rules.nix; do not edit.

    # Do not let an absolute executable with the same basename inherit an
    # allow decision intended for a command resolved through the managed PATH.
    ${lib.concatMapStringsSep "\n" mkCodexHostExecutable codexAllowedExecutables}

    ${lib.concatMapStringsSep "\n" mkCodexRule prefixRules}
  '';
in
if duplicateClaudePatterns != [ ] then
  throw "duplicate Claude command policy patterns: ${builtins.toJSON duplicateClaudePatterns}"
else if duplicateCodexPatterns != [ ] then
  throw "duplicate Codex command policy patterns: ${builtins.toJSON duplicateCodexPatterns}"
else if duplicateCommandOptionMatches != [ ] then
  throw "duplicate command option policy matches: ${builtins.toJSON duplicateCommandOptionMatches}"
else if mixedCodexExecutableDecisions != [ ] then
  throw "Codex command policy mixes allow and forbidden for executables: ${builtins.toJSON mixedCodexExecutableDecisions}"
else
  {
    inherit
      codexAllowedExecutables
      codexRulesContent
      fdForbiddenOptions
      mkClaudePermissions
      prefixRules
      ;
    rules = checkedRules;
  }
