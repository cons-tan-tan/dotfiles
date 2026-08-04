{
  den,
  lib,
  ...
}:
let
  forwardWindows =
    { class, aspect-chain }:
    den.batteries.forward {
      each = lib.singleton class;
      fromClass = _: "windows";
      intoClass = _: "homeManager";
      intoPath = _: [ ];
      fromAspect = _: lib.head aspect-chain;
      guard =
        { config, options, ... }:
        _:
        lib.mkIf (
          options ? dotfiles.windows
          && config.dotfiles.platform.windowsCompanion
          && config.dotfiles.platform.environment == "wsl"
        );
    };
in
{
  den.classes.windows.description = "Windows companion resources forwarded into typed Home Manager options";

  den.aspects.windows-forward = {
    name = "class/windows";
    includes = [ forwardWindows ];
  };
}
