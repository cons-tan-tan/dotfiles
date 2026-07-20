{ lib, ... }:
{
  options.dotfiles.hcom.enable = lib.mkEnableOption "hcom CLI, hooks, and agent skill";
}
