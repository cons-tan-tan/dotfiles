_final: prev:
let
  hcomPackages = prev.callPackage ../packages/hcom { };
in
{
  inherit (hcomPackages) hcom hcom-claude-hooks hcom-codex-hooks;
}
