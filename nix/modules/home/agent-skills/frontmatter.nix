# skill metadata を変換するための純関数群。
{ lib }:
rec {
  utf8Bom = builtins.fromJSON ''"\uFEFF"'';

  utf8ContinuationBytes = map (
    value: builtins.substring 1 1 (builtins.fromJSON ''"\u00${lib.toHexString value}"'')
  ) (lib.range 128 191);

  utf8CodePointLength =
    text:
    let
      bytes = lib.genList (index: builtins.substring index 1 text) (builtins.stringLength text);
    in
    builtins.length (lib.filter (byte: !builtins.elem byte utf8ContinuationBytes) bytes);

  trimLeft =
    text:
    if lib.hasPrefix " " text then
      trimLeft (lib.removePrefix " " text)
    else if lib.hasPrefix "\t" text then
      trimLeft (lib.removePrefix "\t" text)
    else
      text;

  trimRight =
    text:
    if lib.hasSuffix " " text then
      trimRight (lib.removeSuffix " " text)
    else if lib.hasSuffix "\t" text then
      trimRight (lib.removeSuffix "\t" text)
    else
      text;

  trimWhitespace = text: trimRight (trimLeft text);

  isYamlBlockEmptyLine = line: builtins.match "^ *$" line != null;

  leadingSpaceCount =
    text:
    let
      length = builtins.stringLength text;
      count =
        index:
        if index < length && builtins.substring index 1 text == " " then count (index + 1) else index;
    in
    count 0;

  removeLeadingSpaces =
    count: text:
    if count == 0 || !lib.hasPrefix " " text then
      text
    else
      removeLeadingSpaces (count - 1) (lib.removePrefix " " text);

  # YAML の plain / quoted scalar にある、quote 外の inline comment だけを
  # 除く。UTF-8 の非ASCII byteは構文判定せず、そのまま連結する。
  stripYamlInlineComment =
    text:
    let
      normalized = trimWhitespace text;
      length = builtins.stringLength normalized;
      quoteStyle =
        if lib.hasPrefix "'" normalized then
          "single"
        else if lib.hasPrefix "\"" normalized then
          "double"
        else
          "plain";
      scan =
        index: inSingleQuote: inDoubleQuote: escaped: result:
        if index >= length then
          trimRight result
        else
          let
            character = builtins.substring index 1 normalized;
            nextCharacter = if index + 1 < length then builtins.substring (index + 1) 1 normalized else "";
            previousIsWhitespace =
              index == 0
              || builtins.elem (builtins.substring (index - 1) 1 normalized) [
                " "
                "\t"
              ];
          in
          if !inSingleQuote && !inDoubleQuote && character == "#" && previousIsWhitespace then
            trimRight result
          else if inSingleQuote && character == "'" && nextCharacter == "'" then
            scan (index + 2) true false false (result + "''")
          else if quoteStyle == "single" && character == "'" then
            scan (index + 1) (!inSingleQuote) false false (result + character)
          else if quoteStyle == "double" && character == "\"" && !escaped then
            scan (index + 1) false (!inDoubleQuote) false (result + character)
          else
            scan (index + 1) inSingleQuote inDoubleQuote (inDoubleQuote && character == "\\" && !escaped) (
              result + character
            );
    in
    scan 0 false false false "";

  takeWhile =
    predicate: values:
    if values == [ ] || !predicate (builtins.head values) then
      [ ]
    else
      [ (builtins.head values) ] ++ takeWhile predicate (builtins.tail values);

  splitTrailingBlankLines =
    lines:
    let
      reversed = lib.reverseList lines;
      drop =
        count: remaining:
        if remaining != [ ] && isYamlBlockEmptyLine (builtins.head remaining) then
          drop (count + 1) (builtins.tail remaining)
        else
          {
            core = lib.reverseList remaining;
            trailingBlankCount = count;
          };
    in
    drop 0 reversed;

  foldYamlBlockLines =
    lines:
    let
      isEmpty = isYamlBlockEmptyLine;
      isMoreIndented = line: !isEmpty line && (lib.hasPrefix " " line || lib.hasPrefix "\t" line);
      fold =
        current: remaining:
        if remaining == [ ] then
          current
        else
          let
            next = builtins.head remaining;
            nextNonEmpty = lib.findFirst (line: !isEmpty line) null remaining;
            separator =
              if isEmpty current then
                "\n"
              else if isEmpty next then
                if isMoreIndented current || (nextNonEmpty != null && isMoreIndented nextNonEmpty) then "\n" else ""
              else if isMoreIndented current || isMoreIndented next then
                "\n"
              else
                " ";
          in
          current + separator + fold next (builtins.tail remaining);
    in
    if lines == [ ] then "" else fold (builtins.head lines) (builtins.tail lines);

  normalizeText =
    text:
    lib.removePrefix utf8Bom (
      builtins.replaceStrings
        [
          "\r\n"
          "\r"
        ]
        [
          "\n"
          "\n"
        ]
        text
    );

  # SKILL.md を YAML frontmatter と本文に分ける。frontmatter が無い場合は
  # 全体を本文として扱う。
  splitFrontmatter =
    text:
    let
      normalized = normalizeText text;
      lines = lib.splitString "\n" normalized;
      hasOpeningDelimiter = lines != [ ] && builtins.head lines == "---";
      findClosingDelimiter =
        frontmatterLines: remaining:
        if remaining == [ ] then
          null
        else if builtins.head remaining == "---" then
          {
            inherit frontmatterLines;
            bodyLines = builtins.tail remaining;
          }
        else
          findClosingDelimiter (frontmatterLines ++ [ (builtins.head remaining) ]) (builtins.tail remaining);
      split = if hasOpeningDelimiter then findClosingDelimiter [ ] (builtins.tail lines) else null;
    in
    if hasOpeningDelimiter && split == null then
      throw "unterminated skill frontmatter"
    else if split == null then
      {
        frontmatter = "";
        body = normalized;
      }
    else
      {
        frontmatter = "---\n${lib.concatStringsSep "\n" split.frontmatterLines}\n---\n";
        body = lib.concatStringsSep "\n" split.bodyLines;
      };

  setFrontmatterField =
    key: value: original:
    let
      s = splitFrontmatter original;
      fieldLine = "${key}: ${value}";
      hasField = line: lib.hasPrefix "${key}:" line;
    in
    if s.frontmatter == "" then
      "---\n${fieldLine}\n---\n${s.body}"
    else
      let
        lines = lib.splitString "\n" s.frontmatter;
        hasExistingField = lib.any hasField lines;
        updateState =
          state: line:
          let
            isContinuation = line == "" || lib.hasPrefix " " line || lib.hasPrefix "\t" line;
          in
          if state.skipContinuation && isContinuation then
            state
          else if hasField line then
            {
              skipContinuation = true;
              lines = state.lines ++ [ fieldLine ];
            }
          else
            {
              skipContinuation = false;
              lines = state.lines ++ [ line ];
            };
        updatedLinesWithState =
          if hasExistingField then
            lib.foldl' updateState {
              skipContinuation = false;
              lines = [ ];
            } lines
          else
            {
              skipContinuation = false;
              lines = [
                (builtins.head lines)
                fieldLine
              ]
              ++ builtins.tail lines;
            };
        updatedLines = updatedLinesWithState.lines;
      in
      lib.concatStringsSep "\n" updatedLines + s.body;

  # top-level frontmatter のうち許可した field とその継続行だけを残す。
  # 未知の YAML 構文を field の継続として扱わないことで fail closed にする。
  filterFrontmatterFields =
    allowedFields: original:
    let
      s = splitFrontmatter original;
      frontmatterContent = lib.removeSuffix "\n---\n" (lib.removePrefix "---\n" s.frontmatter);
      lines = lib.splitString "\n" frontmatterContent;
      filterState =
        state: line:
        let
          fieldMatch = builtins.match "^([A-Za-z0-9_-]+):.*$" line;
          isField = fieldMatch != null;
          isIndented = lib.hasPrefix " " line || lib.hasPrefix "\t" line;
          isIgnorableTopLevel = line == "" || lib.hasPrefix "#" line;
          keep =
            if isField then
              builtins.elem (builtins.head fieldMatch) allowedFields
            else if !isIndented && !isIgnorableTopLevel then
              false
            else
              state.keep;
        in
        {
          inherit keep;
          lines = state.lines ++ lib.optional keep line;
        };
      filtered = lib.foldl' filterState {
        keep = false;
        lines = [ ];
      } lines;
    in
    if s.frontmatter == "" then
      original
    else
      "---\n${lib.concatStringsSep "\n" filtered.lines}\n---\n${s.body}";

  frontmatterFieldNames =
    original:
    let
      s = splitFrontmatter original;
      frontmatterContent = lib.removeSuffix "\n---\n" (lib.removePrefix "---\n" s.frontmatter);
      lines = lib.splitString "\n" frontmatterContent;
      parsed =
        lib.foldl'
          (
            state: line:
            let
              fieldMatch = builtins.match "^([A-Za-z0-9_-]+):.*$" line;
              isIndented = lib.hasPrefix " " line || lib.hasPrefix "\t" line;
              isIgnorable = trimWhitespace line == "" || lib.hasPrefix "#" (trimLeft line);
            in
            if fieldMatch != null then
              {
                hasField = true;
                fields = state.fields ++ [ (builtins.head fieldMatch) ];
                invalidLines = state.invalidLines;
              }
            else if isIgnorable || (isIndented && state.hasField) then
              state
            else
              state
              // {
                invalidLines = state.invalidLines ++ [ line ];
              }
          )
          {
            hasField = false;
            fields = [ ];
            invalidLines = [ ];
          }
          lines;
    in
    assert lib.assertMsg (parsed.invalidLines == [ ])
      "skill frontmatter contains unsupported top-level syntax: ${lib.concatStringsSep ", " parsed.invalidLines}";
    lib.unique parsed.fields;

  unknownAttrs =
    allowed: attrs: lib.filter (name: !builtins.elem name allowed) (builtins.attrNames attrs);

  validateKnownAttrs =
    context: allowed: attrs:
    let
      unknown = unknownAttrs allowed attrs;
    in
    assert lib.assertMsg (
      unknown == [ ]
    ) "${context}: unknown attributes: ${lib.concatStringsSep ", " unknown}";
    attrs;

  isFrontmatterFieldName = name: builtins.match "^[A-Za-z0-9_-]+$" name != null;

  isSkillName =
    name:
    builtins.isString name
    && builtins.stringLength name <= 64
    && builtins.match "^[a-z0-9]+(-[a-z0-9]+)*$" name != null;

  validateFrontmatterFieldNames =
    context: names:
    assert lib.assertMsg (builtins.isList names) "${context} must be a list";
    assert lib.assertMsg (lib.all builtins.isString names) "${context} must contain only strings";
    assert lib.assertMsg (lib.all isFrontmatterFieldName names)
      "${context} contains an invalid frontmatter field name";
    names;

  validateReplacement =
    context: replacement:
    assert lib.assertMsg (builtins.isAttrs replacement) "${context} must be an attribute set";
    let
      checked = validateKnownAttrs context [ "from" "to" ] replacement;
    in
    assert lib.assertMsg (checked ? from) "${context}.from is required";
    assert lib.assertMsg (checked ? to) "${context}.to is required";
    assert lib.assertMsg (builtins.isString checked.from) "${context}.from must be a string";
    assert lib.assertMsg (checked.from != "") "${context}.from must not be empty";
    assert lib.assertMsg (builtins.isString checked.to) "${context}.to must be a string";
    {
      inherit (checked) from to;
    };

  # sources.nix の customization DSL を正規化し、未知の key や誤った型を
  # eval 時に拒否する。設定 typo を黙って無視すると policy が fail open に
  # なるため、各階層を closed schema として扱う。
  validateCustomization =
    context: value:
    assert lib.assertMsg (builtins.isAttrs value) "${context} must be an attribute set";
    let
      customization = validateKnownAttrs context [
        "frontmatter"
        "body"
        "disableAutomaticInvocation"
      ] value;
      rawFrontmatter = customization.frontmatter or { };
      rawBody = customization.body or { };
    in
    assert lib.assertMsg (builtins.isAttrs rawFrontmatter)
      "${context}.frontmatter must be an attribute set";
    assert lib.assertMsg (builtins.isAttrs rawBody) "${context}.body must be an attribute set";
    let
      frontmatter = validateKnownAttrs "${context}.frontmatter" [
        "set"
        "inheritFields"
        "excludeFields"
      ] rawFrontmatter;
      body = validateKnownAttrs "${context}.body" [
        "prepend"
        "replacements"
      ] rawBody;
      set = frontmatter.set or { };
      inheritFields = validateFrontmatterFieldNames ("${context}.frontmatter.inheritFields") (
        frontmatter.inheritFields or [ ]
      );
      excludeFields = validateFrontmatterFieldNames ("${context}.frontmatter.excludeFields") (
        frontmatter.excludeFields or [ ]
      );
      prepend = body.prepend or "";
      rawReplacements = body.replacements or [ ];
      disableAutomaticInvocation = customization.disableAutomaticInvocation or false;
    in
    assert lib.assertMsg (builtins.isAttrs set) "${context}.frontmatter.set must be an attribute set";
    assert lib.assertMsg (lib.all isFrontmatterFieldName (
      builtins.attrNames set
    )) "${context}.frontmatter.set contains an invalid frontmatter field name";
    assert lib.assertMsg (lib.all (field: !builtins.hasAttr field set || builtins.isString set.${field})
      [
        "name"
        "description"
      ]
    ) "${context}.frontmatter.set name and description values must be strings";
    assert lib.assertMsg (lib.all
      (
        name:
        !builtins.elem name [
          "name"
          "description"
        ]
      )
      excludeFields
    ) "${context}.frontmatter.excludeFields cannot exclude required name or description fields";
    assert lib.assertMsg (builtins.isString prepend) "${context}.body.prepend must be a string";
    assert lib.assertMsg (builtins.isList rawReplacements)
      "${context}.body.replacements must be a list";
    assert lib.assertMsg (builtins.isBool disableAutomaticInvocation)
      "${context}.disableAutomaticInvocation must be a boolean";
    {
      frontmatter = {
        inherit set inheritFields excludeFields;
      };
      body = {
        inherit prepend;
        replacements = map (validateReplacement "${context}.body.replacements[]") rawReplacements;
      };
      inherit disableAutomaticInvocation;
    };

  validateSkillDefinition =
    name: value:
    assert lib.assertMsg (builtins.isAttrs value) "skill ${name} definition must be an attribute set";
    let
      skill = validateKnownAttrs "skill ${name} definition" [
        "root"
        "customization"
      ] value;
      customization = validateCustomization "skill ${name} customization" (skill.customization or { });
    in
    assert lib.assertMsg (skill ? root) "skill ${name} definition requires root";
    assert lib.assertMsg (
      builtins.isPath skill.root || builtins.isString skill.root
    ) "skill ${name} definition root must be a path or string";
    {
      inherit (skill) root;
      inherit customization;
      hasCustomization =
        builtins.attrNames customization.frontmatter.set != [ ]
        || customization.frontmatter.inheritFields != [ ]
        || customization.frontmatter.excludeFields != [ ]
        || customization.body.prepend != ""
        || customization.body.replacements != [ ]
        || customization.disableAutomaticInvocation;
    };

  setFrontmatterValues =
    values: original:
    lib.foldl' (text: key: setFrontmatterField key (builtins.toJSON values.${key}) text) original (
      builtins.attrNames values
    );

  transformBody =
    transform: original:
    let
      s = splitFrontmatter original;
    in
    s.frontmatter + transform s.body;

  applyCustomization =
    customization: original:
    let
      frontmatter = customization.frontmatter or { };
      body = customization.body or { };
      replacements = body.replacements or [ ];
      withFrontmatter = setFrontmatterValues (frontmatter.set or { }) original;
      withReplacements = transformBody (
        text:
        builtins.replaceStrings (map (replacement: replacement.from) replacements) (map (
          replacement: replacement.to
        ) replacements) text
      ) withFrontmatter;
    in
    transformBody (text: (body.prepend or "") + text) withReplacements;

  disableModelInvocation = setFrontmatterField "disable-model-invocation" "true";

  findFrontmatterFields =
    key: text:
    let
      s = splitFrontmatter text;
      content = lib.removeSuffix "\n---\n" (lib.removePrefix "---\n" s.frontmatter);
      lines = lib.splitString "\n" content;
      findAll =
        remaining:
        if remaining == [ ] then
          [ ]
        else
          let
            line = builtins.head remaining;
            match = builtins.match "^${key}:[ ]*(.*)$" line;
            rest = findAll (builtins.tail remaining);
          in
          if match != null then
            [
              {
                inlineValue = builtins.head match;
                continuation = takeWhile (
                  continuationLine:
                  continuationLine == "" || lib.hasPrefix " " continuationLine || lib.hasPrefix "\t" continuationLine
                ) (builtins.tail remaining);
              }
            ]
            ++ rest
          else
            rest;
    in
    if s.frontmatter == "" then [ ] else findAll lines;

  frontmatterStringValue =
    field:
    let
      inlineValue = trimWhitespace (stripYamlInlineComment field.inlineValue);
      isBlockScalar = builtins.match "^[|>]([+-]?[1-9]?|[1-9][+-]?)$" inlineValue != null;
      indicatorCharacters = lib.genList (index: builtins.substring index 1 inlineValue) (
        builtins.stringLength inlineValue
      );
      explicitIndentCharacter = lib.findFirst (
        character: builtins.match "^[1-9]$" character != null
      ) null indicatorCharacters;
      firstContentLine = lib.findFirst (line: !isYamlBlockEmptyLine line) null field.continuation;
      blockIndent =
        if explicitIndentCharacter != null then
          builtins.fromJSON explicitIndentCharacter
        else if firstContentLine != null then
          leadingSpaceCount firstContentLine
        else
          0;
      hasValidBlockIndent =
        blockIndent > 0
        && lib.all (
          line:
          isYamlBlockEmptyLine line || (!lib.hasPrefix "\t" line && leadingSpaceCount line >= blockIndent)
        ) field.continuation;
      decodedBlockLines = map (removeLeadingSpaces blockIndent) field.continuation;
      blockHasValue = lib.any (line: trimWhitespace line != "") decodedBlockLines;
      keepTrailingLines = lib.hasInfix "+" inlineValue;
      stripTrailingLines = lib.hasInfix "-" inlineValue;
      splitBlockLines = splitTrailingBlankLines decodedBlockLines;
      blockContent =
        if lib.hasPrefix ">" inlineValue then
          foldYamlBlockLines splitBlockLines.core
        else
          lib.concatStringsSep "\n" splitBlockLines.core;
      trailingNewlineCount =
        if stripTrailingLines then
          0
        else if keepTrailingLines then
          1 + splitBlockLines.trailingBlankCount
        else
          1;
      blockValue = blockContent + lib.concatStrings (lib.replicate trailingNewlineCount "\n");
      isDoubleQuoted =
        builtins.stringLength inlineValue >= 2
        && lib.hasPrefix "\"" inlineValue
        && lib.hasSuffix "\"" inlineValue;
      jsonValue =
        if isDoubleQuoted then
          builtins.tryEval (builtins.fromJSON inlineValue)
        else
          {
            success = false;
            value = null;
          };
      isSingleQuoted =
        builtins.stringLength inlineValue >= 2
        && lib.hasPrefix "'" inlineValue
        && lib.hasSuffix "'" inlineValue;
      singleQuotedInner = lib.removeSuffix "'" (lib.removePrefix "'" inlineValue);
      singleQuotedInnerLength = builtins.stringLength singleQuotedInner;
      hasValidSingleQuotePairs =
        let
          scan =
            index:
            if index >= singleQuotedInnerLength then
              true
            else if builtins.substring index 1 singleQuotedInner == "'" then
              index + 1 < singleQuotedInnerLength
              && builtins.substring (index + 1) 1 singleQuotedInner == "'"
              && scan (index + 2)
            else
              scan (index + 1);
        in
        scan 0;
      singleQuotedValue = builtins.replaceStrings [ "''" ] [ "'" ] singleQuotedInner;
      lowerValue = lib.toLower inlineValue;
      isNonStringPlainScalar =
        builtins.elem lowerValue [
          "null"
          "~"
          "true"
          "false"
          "yes"
          "no"
          "on"
          "off"
          ".nan"
          ".inf"
          "+.inf"
          "-.inf"
        ]
        || builtins.match "^[-+]?[0-9]+([.][0-9]+)?$" inlineValue != null
        || lib.any (prefix: lib.hasPrefix prefix inlineValue) [
          "["
          "{"
          "!"
          "&"
          "*"
          "|"
          ">"
          "'"
          "\""
        ];
    in
    if isBlockScalar then
      if hasValidBlockIndent && blockHasValue then blockValue else null
    else if isDoubleQuoted then
      if jsonValue.success && builtins.isString jsonValue.value && jsonValue.value != "" then
        jsonValue.value
      else
        null
    else if isSingleQuoted then
      if hasValidSingleQuotePairs && singleQuotedValue != "" then singleQuotedValue else null
    else if inlineValue == "" || lib.hasPrefix "#" inlineValue || isNonStringPlainScalar then
      null
    else
      inlineValue;

  validateRequiredFrontmatter =
    expectedName: text:
    let
      s = splitFrontmatter text;
      names = findFrontmatterFields "name" text;
      descriptions = findFrontmatterFields "description" text;
      name = if builtins.length names == 1 then frontmatterStringValue (builtins.head names) else null;
      description =
        if builtins.length descriptions == 1 then
          frontmatterStringValue (builtins.head descriptions)
        else
          null;
    in
    assert lib.assertMsg (
      s.frontmatter != ""
    ) "skill ${expectedName}: SKILL.md requires YAML frontmatter";
    assert lib.assertMsg (
      builtins.length names == 1
    ) "skill ${expectedName}: frontmatter must contain exactly one name field";
    assert lib.assertMsg (
      builtins.length descriptions == 1
    ) "skill ${expectedName}: frontmatter must contain exactly one description field";
    assert lib.assertMsg (
      name == expectedName
    ) "skill ${expectedName}: frontmatter.name must be a string matching its distribution name";
    assert lib.assertMsg (
      description != null
    ) "skill ${expectedName}: frontmatter.description must be a non-empty string";
    assert lib.assertMsg (
      utf8CodePointLength description <= 1024
    ) "skill ${expectedName}: frontmatter.description must not exceed 1024 characters";
    assert lib.assertMsg (
      builtins.match ".*<[^>]+>.*" (builtins.replaceStrings [ "\n" ] [ " " ] description) == null
    ) "skill ${expectedName}: frontmatter.description must not contain XML tags";
    text;

  # Upstream filtering, local overrides, and invocation policy are intentionally
  # one pipeline so callers cannot accidentally change their security-sensitive
  # ordering.
  prepareSkill =
    {
      name,
      defaultInheritedFields,
      customization ? { },
      requireExplicitFieldDecisions ? false,
    }:
    original:
    let
      context = "skill ${name} customization";
      checkedCustomization = validateCustomization context customization;
      frontmatter = checkedCustomization.frontmatter;
      source = splitFrontmatter original;
      sourceFields = frontmatterFieldNames original;
      explicitInheritedFields = frontmatter.inheritFields;
      explicitExcludedFields = frontmatter.excludeFields;
      explicitlyClassifiedFields = lib.unique (
        defaultInheritedFields ++ explicitInheritedFields ++ explicitExcludedFields
      );
      unclassifiedFields = lib.filter (
        field: !builtins.elem field explicitlyClassifiedFields
      ) sourceFields;
      declaredFieldsNotInSource = lib.filter (field: !builtins.elem field sourceFields) (
        lib.unique (explicitInheritedFields ++ explicitExcludedFields)
      );
      conflictingFieldDecisions = lib.intersectLists explicitInheritedFields explicitExcludedFields;
      inheritedFields = lib.unique (defaultInheritedFields ++ frontmatter.inheritFields);
      effectiveInheritedFields = lib.subtractLists frontmatter.excludeFields inheritedFields;
      filtered = filterFrontmatterFields effectiveInheritedFields original;
      customized = applyCustomization checkedCustomization filtered;
      transformedSkillMd =
        if checkedCustomization.disableAutomaticInvocation then
          disableModelInvocation customized
        else
          customized;
      skillMd = validateRequiredFrontmatter name transformedSkillMd;
    in
    assert lib.assertMsg (isSkillName name)
      "skill distribution name must use 1-64 lowercase letters, digits, and hyphens: ${name}";
    assert lib.assertMsg (
      source.frontmatter != ""
    ) "skill ${name}: upstream SKILL.md requires YAML frontmatter";
    assert lib.assertMsg (conflictingFieldDecisions == [ ])
      "${context}.frontmatter fields cannot be both inherited and excluded: ${lib.concatStringsSep ", " conflictingFieldDecisions}";
    assert lib.assertMsg (declaredFieldsNotInSource == [ ])
      "${context}.frontmatter decisions reference fields missing from upstream: ${lib.concatStringsSep ", " declaredFieldsNotInSource}";
    assert lib.assertMsg (!requireExplicitFieldDecisions || unclassifiedFields == [ ])
      "${context}.frontmatter has unclassified upstream fields: ${lib.concatStringsSep ", " unclassifiedFields}";
    builtins.seq skillMd {
      inherit skillMd;
      frontmatterWasFiltered = filtered != original;
      inherit (checkedCustomization) disableAutomaticInvocation;
    };

  codexImplicitInvocationPolicy = ''
    policy:
      allow_implicit_invocation: false
  '';

  ensureTrailingNewline = text: if text == "" || lib.hasSuffix "\n" text then text else text + "\n";

  disableCodexImplicitInvocation =
    text:
    let
      lines = lib.splitString "\n" text;
      hasPolicy = lib.any (line: line == "policy:") lines;
      hasAllowImplicitInvocation = lib.any (
        line: lib.hasPrefix "  allow_implicit_invocation:" line
      ) lines;
      replaceAllowImplicitInvocation = map (
        line:
        if lib.hasPrefix "  allow_implicit_invocation:" line then
          "  allow_implicit_invocation: false"
        else
          line
      );
      insertUnderPolicy =
        remaining:
        if remaining == [ ] then
          [ ]
        else if builtins.head remaining == "policy:" then
          [
            "policy:"
            "  allow_implicit_invocation: false"
          ]
          ++ builtins.tail remaining
        else
          [ (builtins.head remaining) ] ++ insertUnderPolicy (builtins.tail remaining);
    in
    if text == "" then
      codexImplicitInvocationPolicy
    else if hasAllowImplicitInvocation then
      lib.concatStringsSep "\n" (replaceAllowImplicitInvocation lines)
    else if hasPolicy then
      lib.concatStringsSep "\n" (insertUnderPolicy lines)
    else
      ensureTrailingNewline text + "\n" + codexImplicitInvocationPolicy;

}
