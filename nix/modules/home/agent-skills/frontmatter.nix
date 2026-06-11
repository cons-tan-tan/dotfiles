# SKILL.md の YAML frontmatter を変換するための純関数群。
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

  injectAfterFrontmatter =
    note: original:
    let
      s = splitFrontmatter original;
    in
    s.frontmatter + note + s.body;
}
