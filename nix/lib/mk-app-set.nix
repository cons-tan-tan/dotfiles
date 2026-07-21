# apps (flake 出力) と scripts (CI の shellcheck ゲート) を同じレコードから
# 導出し、scripts への列挙漏れを構造的に防ぐ。
{ lib }:
{
  mkAppSet =
    {
      entries,
      extraApps ? { },
    }:
    let
      duplicateNames = lib.intersectLists (builtins.attrNames entries) (builtins.attrNames extraApps);
    in
    if duplicateNames != [ ] then
      throw "app names must be unique across entries and extraApps: ${builtins.toJSON duplicateNames}"
    else
      {
        apps =
          lib.mapAttrs (_: entry: {
            type = "app";
            meta.description = entry.description;
            program = lib.getExe entry.script;
          }) entries
          // extraApps;
        scripts = lib.mapAttrsToList (_: entry: entry.script) entries;
      };
}
