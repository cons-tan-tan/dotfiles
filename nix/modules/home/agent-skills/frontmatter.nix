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
      updateLine = line: if hasField line then fieldLine else line;
    in
    if s.frontmatter == "" then
      "---\n${fieldLine}\n---\n${s.body}"
    else
      let
        lines = lib.splitString "\n" s.frontmatter;
        updatedLines =
          if lib.any hasField lines then
            map updateLine lines
          else
            [
              (builtins.head lines)
              fieldLine
            ]
            ++ builtins.tail lines;
      in
      lib.concatStringsSep "\n" updatedLines + s.body;

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
