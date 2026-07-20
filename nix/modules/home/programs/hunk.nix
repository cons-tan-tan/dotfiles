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
  # Import the option module without upstream's default package, because the
  # local package supplies the bun2nix context fix.
  imports = [ inputs.hunk.homeManagerModules.hunk ];

  programs.hunk = {
    enable = true;
    enableGitIntegration = true;
    package = if config.my.hostKind == "wsl" then hunk.wslRuntime else hunk.package;
    settings.wrap_lines = true;
  };
}
