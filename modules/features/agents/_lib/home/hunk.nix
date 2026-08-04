{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  hunk = pkgs.dotfilesPackages.hunk;
in
{
  imports = [ inputs.hunk.homeManagerModules.hunk ];

  programs.hunk = {
    enable = true;
    enableGitIntegration = true;
    package = lib.mkDefault hunk.package;
    settings.wrap_lines = true;
  };
}
