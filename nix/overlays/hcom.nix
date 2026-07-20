hcomSource: _final: prev:
let
  hcomPackages = prev.callPackage ../packages/hcom {
    inherit hcomSource;
  };
in
{
  inherit (hcomPackages) hcom hcom-claude-hooks hcom-codex-hooks;
}
