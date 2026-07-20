{ lib }:
let
  eval =
    modules:
    lib.evalModules {
      modules = [ ./hcom.nix ] ++ modules;
    };
in
{
  testHcomDefaultsToDisabled = {
    expr = (eval [ ]).config.dotfiles.hcom.enable;
    expected = false;
  };

  testHcomCanBeEnabledDeclaratively = {
    expr = (eval [ { dotfiles.hcom.enable = true; } ]).config.dotfiles.hcom.enable;
    expected = true;
  };
}
