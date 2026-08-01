{ lib }:
let
  hasOnlyAttrs = allowed: value: lib.all (name: lib.elem name allowed) (builtins.attrNames value);
in
{
  validate =
    tree:
    if
      builtins.isAttrs tree
      && hasOnlyAttrs [ "redirection" ] tree
      && (
        !(tree ? redirection)
        || (
          builtins.isAttrs tree.redirection
          && builtins.attrNames tree.redirection == [ "emptyFile" ]
          && builtins.isBool tree.redirection.emptyFile
        )
      )
    then
      tree
    else
      throw "agentCommandPolicy.shell supports only the boolean leaf redirection.emptyFile";
}
