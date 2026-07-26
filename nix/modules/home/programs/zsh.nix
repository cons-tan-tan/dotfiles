{
  config,
  lib,
  ...
}:
lib.mkIf (config.my.isDarwin || config.my.isWsl) {
  programs.zsh.enable = true;
}
