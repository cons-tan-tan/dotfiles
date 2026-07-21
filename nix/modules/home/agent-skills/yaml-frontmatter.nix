# SKILL.md 等の YAML frontmatter に対する汎用テキスト処理。
# skill 固有の判断 (どのフィールドを許すか等) は skill-policy.nix に置く。
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

  normalizeDescription =
    text:
    lib.concatStringsSep " " (
      lib.filter (line: line != "") (
        map trimWhitespace (
          lib.splitString "\n" (builtins.replaceStrings [ "\r\n" "\r" ] [ "\n" "\n" ] text)
        )
      )
    );

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

  isFrontmatterFieldName = name: builtins.match "^[A-Za-z0-9_-]+$" name != null;

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

  ensureTrailingNewline = text: if text == "" || lib.hasSuffix "\n" text then text else text + "\n";

}
