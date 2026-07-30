# agent非依存の再帰command policyを各backendへ投影する。
{
  lib,
  argv,
  options,
}:
let
  executableTokenPattern = "^[a-zA-Z0-9_][a-zA-Z0-9_+@%.-]*$";
  argvTokenPattern = "^[a-zA-Z0-9_./:+@%=-]+$";
  commandOptionPattern = "^(--[a-zA-Z0-9][a-zA-Z0-9-]*|-[a-zA-Z0-9])$";

  decisionFor = allowed: if allowed then "allow" else "forbidden";
  justificationFor =
    allowed: subject:
    "${if allowed then "Allowed" else "Forbidden"} by the shared agent command policy: ${subject}.";

  flattenArgvTree =
    prefix: tree:
    if !builtins.isAttrs tree then
      throw "agent command policy argv branch must be an attribute set"
    else
      let
        tokens = builtins.attrNames tree;
      in
      if tokens == [ ] then
        throw "agent command policy argv branch must not be empty: ${builtins.toJSON prefix}"
      else
        lib.concatMap (
          token:
          let
            nextPrefix = prefix ++ [ token ];
            value = tree.${token};
            tokenPattern = if prefix == [ ] then executableTokenPattern else argvTokenPattern;
          in
          if builtins.match tokenPattern token == null then
            throw "agent command policy has an invalid argv token: ${builtins.toJSON token}"
          else if builtins.isBool value then
            [
              {
                argvPrefix = nextPrefix;
                allowed = value;
                decision = decisionFor value;
                justification = justificationFor value (lib.escapeShellArgs nextPrefix);
              }
            ]
          else if builtins.isAttrs value then
            flattenArgvTree nextPrefix value
          else
            throw "agent command policy argv leaves must be boolean: ${builtins.toJSON nextPrefix}"
        ) tokens;

  prefixRules = if argv == { } then [ ] else flattenArgvTree [ ] argv;

  optionRules =
    if !builtins.isAttrs options then
      throw "agent command policy options must be an attribute set"
    else
      lib.concatMap (
        command:
        let
          commandOptions = options.${command};
        in
        if builtins.match executableTokenPattern command == null then
          throw "agent command policy has an invalid option command: ${builtins.toJSON command}"
        else if !builtins.isAttrs commandOptions || commandOptions == { } then
          throw "agent command policy option command must contain at least one option: ${builtins.toJSON command}"
        else
          map (
            option:
            let
              allowed = commandOptions.${option};
            in
            if builtins.match commandOptionPattern option == null then
              throw "agent command policy has an invalid command option: ${builtins.toJSON option}"
            else if !builtins.isBool allowed then
              throw "agent command policy option decisions must be boolean: ${
                builtins.toJSON [
                  command
                  option
                ]
              }"
            else
              {
                inherit allowed command option;
                decision = decisionFor allowed;
                justification = justificationFor allowed "${command} option ${option}";
              }
          ) (builtins.attrNames commandOptions)
      ) (builtins.attrNames options);

  unsupportedOptionRules = builtins.filter (rule: rule.command != "fd" || rule.allowed) optionRules;
  checkedOptionRules =
    if unsupportedOptionRules != [ ] then
      throw "agent command policy uses an unsupported option decision: ${builtins.toJSON unsupportedOptionRules}"
    else
      optionRules;

  checkedPrefixRules = builtins.deepSeq prefixRules prefixRules;
  checkedRules = builtins.deepSeq checkedOptionRules (
    if checkedPrefixRules == [ ] && checkedOptionRules == [ ] then
      throw "agent command policy must define at least one decision"
    else
      checkedPrefixRules
  );

  # Claudeは一部のprocess wrapperを剥がして照合するが、可変引数を持つ
  # timeout等をCodexの固定prefixで安全に一般化できないため、ここでは直接の
  # argvだけを投影する。optionsは文字列globでは `--` 境界やshort optionの
  # clusterを保てないため、Claude/Codex共通wrapperだけで検査する。
  claudePatternFor = rule: "Bash(${lib.escapeShellArgs rule.argvPrefix} *)";

  mkClaudePermissions =
    { }:
    let
      patternsFor =
        decision: map claudePatternFor (builtins.filter (rule: rule.decision == decision) checkedRules);
    in
    {
      allow = patternsFor "allow";
      deny = patternsFor "forbidden";
    };

  codexAllowedExecutables = lib.unique (
    map (rule: builtins.head rule.argvPrefix) (
      builtins.filter (rule: rule.decision == "allow") checkedRules
    )
  );
  fdForbiddenOptions = map (rule: rule.option) checkedOptionRules;

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

    ${lib.concatMapStringsSep "\n" mkCodexRule checkedRules}
  '';
in
builtins.deepSeq checkedRules {
  inherit
    codexAllowedExecutables
    codexRulesContent
    fdForbiddenOptions
    mkClaudePermissions
    ;
  prefixRules = checkedRules;
  rules = checkedRules;
}
