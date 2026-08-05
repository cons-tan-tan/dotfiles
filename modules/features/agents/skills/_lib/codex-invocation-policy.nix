# Codex 向け openai.yaml に implicit invocation 無効化ポリシーを注入する。
# YAML テキスト処理は yaml-frontmatter.nix の汎用関数を使う。
{ lib }:
let
  yaml = import ./yaml-frontmatter.nix { inherit lib; };
  inherit (yaml) ensureTrailingNewline;
in
rec {
  codexImplicitInvocationPolicy = ''
    policy:
      allow_implicit_invocation: false
  '';

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
