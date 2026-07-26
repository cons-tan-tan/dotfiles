{
  config,
  lib,
  ...
}:
lib.mkIf config.my.isWsl {
  programs.zsh.enable = true;
}
