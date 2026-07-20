# skill metadata を変換するための純関数群。
{ lib }:
rec {
  # SKILL.md を YAML frontmatter と本文に分ける。frontmatter が無い場合は
  # 全体を本文として扱う。
  splitFrontmatter =
    text:
    let
      parts = lib.splitString "\n---\n" text;
      hasFm = builtins.length parts > 1 && lib.hasPrefix "---\n" text;
    in
    {
      frontmatter = if hasFm then builtins.head parts + "\n---\n" else "";
      body = if hasFm then lib.concatStringsSep "\n---\n" (builtins.tail parts) else text;
    };

  replaceFrontmatter = frontmatter: original: frontmatter + (splitFrontmatter original).body;

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

  disableModelInvocation = setFrontmatterField "disable-model-invocation" "true";

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

  injectAfterFrontmatter =
    note: original:
    let
      s = splitFrontmatter original;
    in
    s.frontmatter + note + s.body;
}
