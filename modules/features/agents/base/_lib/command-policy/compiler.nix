# agent非依存の再帰command policyをnative allowと共通guardへ投影する。
{
  lib,
  commands,
  shell ? { },
  shellfirm ? {
    enabled = false;
    minimumSeverity = "High";
    categories = { };
    ruleNamespaces = { };
    rules = { };
  },
}:
let
  executableTokenPattern = "^[a-zA-Z0-9_][a-zA-Z0-9_+@%.-]*$";
  argvTokenPattern = "^[a-zA-Z0-9_./:+@%=-]+$";
  commandOptionPattern = "^(--[a-zA-Z0-9][a-zA-Z0-9-]*|-[a-zA-Z0-9])$";
  severities = [
    "Info"
    "Low"
    "Medium"
    "High"
    "Critical"
  ];

  isUnique = values: builtins.length values == builtins.length (lib.unique values);
  isNonBlankString = value: builtins.isString value && builtins.match "^[[:space:]]*$" value == null;
  isSelectorToken = value: value != "" && !lib.hasInfix ":" value;
  hasOnlyAttrs = allowed: value: lib.all (name: lib.elem name allowed) (builtins.attrNames value);

  decisionFor = allowed: if allowed then "allow" else "forbidden";
  justificationFor =
    allowed: subject:
    "${if allowed then "Allowed" else "Forbidden"} by the shared agent command policy: ${subject}.";

  mkPrefixRule = prefix: allowed: {
    argvPrefix = prefix;
    inherit allowed;
    decision = decisionFor allowed;
    justification = justificationFor allowed (lib.escapeShellArgs prefix);
  };

  flattenCommandTree =
    prefix: tree:
    if !builtins.isAttrs tree then
      throw "agent command policy command branch must be an attribute set"
    else
      let
        tokens = builtins.attrNames tree;
      in
      if tokens == [ ] then
        throw "agent command policy command branch must not be empty: ${builtins.toJSON prefix}"
      else
        lib.concatMap (
          token:
          let
            nextPrefix = prefix ++ [ token ];
            value = tree.${token};
            tokenPattern = if prefix == [ ] then executableTokenPattern else argvTokenPattern;
          in
          if builtins.match tokenPattern token == null then
            throw "agent command policy has an invalid command token: ${builtins.toJSON token}"
          else if builtins.isBool value then
            [
              {
                prefixRule = mkPrefixRule nextPrefix value;
                semanticRule = null;
              }
            ]
          else if builtins.isAttrs value && value ? decision then
            if
              !builtins.isBool value.decision
              || !hasOnlyAttrs [
                "decision"
                "deny"
                "guidance"
                "optionSyntax"
              ] value
              || !(value ? deny)
              || !(value ? optionSyntax)
              || !builtins.isList value.deny
              || value.deny == [ ]
              || !builtins.isAttrs value.optionSyntax
            then
              throw "agent command policy command terminal is invalid: ${builtins.toJSON nextPrefix}"
            else if (value ? guidance) && !isNonBlankString value.guidance then
              throw "agent command policy command guidance must be non-empty: ${builtins.toJSON nextPrefix}"
            else
              [
                {
                  prefixRule = mkPrefixRule nextPrefix value.decision;
                  semanticRule = {
                    commandPrefix = nextPrefix;
                    optionSyntax = normalizeOptionSyntax nextPrefix value.optionSyntax;
                    deny = map (normalizeDenyRule nextPrefix) value.deny;
                  }
                  // lib.optionalAttrs (value ? guidance) {
                    inherit (value) guidance;
                  };
                }
              ]
          else if builtins.isAttrs value then
            flattenCommandTree nextPrefix value
          else
            throw "agent command policy command leaves must be boolean or semantic terminals: ${builtins.toJSON nextPrefix}"
        ) tokens;

  commandEntries = if commands == { } then [ ] else flattenCommandTree [ ] commands;
  prefixRules = map (entry: entry.prefixRule) commandEntries;
  nativePrefixRules = builtins.filter (rule: rule.allowed) prefixRules;
  deniedPrefixRules = builtins.filter (rule: !rule.allowed) prefixRules;

  normalizeOptionList =
    label: values:
    if
      !builtins.isList values
      || !lib.all (
        option: builtins.isString option && builtins.match commandOptionPattern option != null
      ) values
    then
      throw "agent command policy ${label} must contain valid command options"
    else if !isUnique values then
      throw "agent command policy ${label} contains duplicate command options"
    else
      values;

  normalizeOptionGroup =
    values:
    let
      normalized = normalizeOptionList "semantic deny option group" values;
    in
    if normalized == [ ] then
      throw "agent command policy semantic deny option groups must not be empty"
    else
      normalized;

  normalizeOptionSyntax =
    commandPrefix: value:
    if
      !builtins.isAttrs value
      || !hasOnlyAttrs [
        "optionalEquals"
        "valueTaking"
      ] value
    then
      throw "agent command policy semantic optionSyntax is invalid: ${builtins.toJSON commandPrefix}"
    else
      let
        valueTaking = normalizeOptionList "semantic optionSyntax.valueTaking" (value.valueTaking or [ ]);
        optionalEquals = normalizeOptionList "semantic optionSyntax.optionalEquals" (
          value.optionalEquals or [ ]
        );
      in
      if !isUnique (valueTaking ++ optionalEquals) then
        throw "agent command policy semantic option aliases must not overlap: ${builtins.toJSON commandPrefix}"
      else
        { inherit optionalEquals valueTaking; };

  normalizeDenyRule =
    commandPrefix: rule:
    if
      !builtins.isAttrs rule
      || !hasOnlyAttrs [
        "alternatives"
        "reason"
        "when"
      ] rule
      || !(rule ? when)
      || !builtins.isAttrs rule.when
      || !hasOnlyAttrs [ "options" ] rule.when
      || !(rule.when ? options)
      || !builtins.isAttrs rule.when.options
      || !hasOnlyAttrs [ "all" ] rule.when.options
      || !(rule.when.options ? all)
      || !builtins.isList rule.when.options.all
      || rule.when.options.all == [ ]
    then
      throw "agent command policy semantic deny condition is invalid: ${builtins.toJSON commandPrefix}"
    else
      let
        optionGroups = map normalizeOptionGroup rule.when.options.all;
        aliases = lib.concatLists optionGroups;
      in
      if !isUnique aliases then
        throw "agent command policy semantic deny option aliases must be unique: ${builtins.toJSON commandPrefix}"
      else if !(rule ? reason) || !isNonBlankString rule.reason then
        throw "agent command policy semantic deny reason must be non-empty: ${builtins.toJSON commandPrefix}"
      else if
        !(rule ? alternatives)
        || !builtins.isList rule.alternatives
        || rule.alternatives == [ ]
        || !lib.all isNonBlankString rule.alternatives
        || !isUnique rule.alternatives
      then
        throw "agent command policy semantic deny alternatives are invalid: ${builtins.toJSON commandPrefix}"
      else
        {
          inherit optionGroups;
          inherit (rule) alternatives reason;
        };

  semanticRules = lib.filter (rule: rule != null) (map (entry: entry.semanticRule) commandEntries);

  shellPolicy = (import ./shell-policy-schema.nix { inherit lib; }).validate shell;

  checkSelectorMap =
    label: values:
    if !builtins.isAttrs values then
      throw "agent command policy Shellfirm ${label} must be an attribute set"
    else
      builtins.mapAttrs (
        name: decision:
        if !isSelectorToken name then
          throw "agent command policy Shellfirm ${label} has an invalid selector: ${builtins.toJSON name}"
        else if !builtins.isBool decision then
          throw "agent command policy Shellfirm ${label} leaves must be boolean"
        else
          decision
      ) values;

  flattenShellfirmRules =
    prefix: tree:
    if !builtins.isAttrs tree then
      throw "agent command policy Shellfirm rule branch must be an attribute set"
    else
      let
        tokens = builtins.attrNames tree;
      in
      if prefix != [ ] && tokens == [ ] then
        throw "agent command policy Shellfirm rule branch must not be empty: ${builtins.toJSON prefix}"
      else
        lib.concatMap (
          token:
          let
            value = tree.${token};
            nextPrefix = prefix ++ [ token ];
          in
          if !isSelectorToken token then
            throw "agent command policy has an invalid Shellfirm rule token: ${builtins.toJSON token}"
          else if builtins.isBool value then
            if builtins.length nextPrefix < 2 then
              throw "agent command policy Shellfirm rules require namespace and rule tokens"
            else
              [
                {
                  name = lib.concatStringsSep ":" nextPrefix;
                  inherit value;
                }
              ]
          else if builtins.isAttrs value then
            flattenShellfirmRules nextPrefix value
          else
            throw "agent command policy Shellfirm rule leaves must be boolean: ${builtins.toJSON nextPrefix}"
        ) tokens;

  shellfirmPolicy =
    if
      !builtins.isAttrs shellfirm
      || !hasOnlyAttrs [
        "categories"
        "enabled"
        "minimumSeverity"
        "ruleNamespaces"
        "rules"
      ] shellfirm
      || !(shellfirm ? enabled)
      || !builtins.isBool shellfirm.enabled
      || !(shellfirm ? minimumSeverity)
      || !lib.elem shellfirm.minimumSeverity severities
      || !(shellfirm ? categories)
      || !(shellfirm ? ruleNamespaces)
      || !(shellfirm ? rules)
    then
      throw "agent command policy Shellfirm configuration is invalid"
    else
      {
        inherit (shellfirm) enabled minimumSeverity;
        categories = checkSelectorMap "categories" shellfirm.categories;
        ruleNamespaces = checkSelectorMap "ruleNamespaces" shellfirm.ruleNamespaces;
        rules = builtins.listToAttrs (flattenShellfirmRules [ ] shellfirm.rules);
      };

  shellfirmHasPositiveSelector =
    shellfirmPolicy.enabled
    && (
      lib.any (decision: decision) (builtins.attrValues shellfirmPolicy.categories)
      || lib.any (decision: decision) (builtins.attrValues shellfirmPolicy.ruleNamespaces)
      || lib.any (decision: decision) (builtins.attrValues shellfirmPolicy.rules)
    );

  # Semantic rules come from command terminals and therefore always contribute
  # a prefix rule as well; counting them separately cannot change this decision.
  hasDecision = prefixRules != [ ] || shellPolicy != { } || shellfirmHasPositiveSelector;
  checkedPolicy = builtins.deepSeq [
    prefixRules
    semanticRules
    shellPolicy
    shellfirmPolicy
  ] (if !hasDecision then throw "agent command policy must define at least one decision" else true);

  claudePatternFor = rule: "Bash(${lib.escapeShellArgs rule.argvPrefix} *)";

  mkClaudePermissions =
    { }:
    assert checkedPolicy;
    {
      allow = map claudePatternFor nativePrefixRules;
      deny = [ ];
    };

  codexAllowedExecutables = lib.unique (map (rule: builtins.head rule.argvPrefix) nativePrefixRules);

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
          decision = "allow",
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
    # Generated from the agents feature command policy; do not edit.

    # Do not let an absolute executable with the same basename inherit an
    # allow decision intended for a command resolved through the managed PATH.
    ${lib.concatMapStringsSep "\n" mkCodexHostExecutable codexAllowedExecutables}

    ${lib.concatMapStringsSep "\n" mkCodexRule nativePrefixRules}
  '';

  guardPolicy = {
    schemaVersion = 2;
    exact = map (rule: {
      argvPrefix = rule.argvPrefix;
      decision = "deny";
      reason = rule.justification;
    }) deniedPrefixRules;
    semantic = semanticRules;
    shell = shellPolicy;
    shellfirm = shellfirmPolicy;
    unknown = {
      parseError = "deny";
      dynamicExecutable = "deny";
      dynamicRelevantOption = "deny";
      maxDecodeDepth = 8;
    };
  };
in
assert checkedPolicy;
{
  inherit
    codexAllowedExecutables
    codexRulesContent
    guardPolicy
    mkClaudePermissions
    ;
  prefixRules = nativePrefixRules;
  rules = nativePrefixRules;
}
