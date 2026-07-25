{
  config,
  inputs,
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
    package = if config.my.isWsl then hunk.wslRuntime else hunk.package;
    settings.wrap_lines = true;
  };
}
