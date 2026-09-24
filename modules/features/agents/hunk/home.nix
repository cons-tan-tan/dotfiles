{
  inputs,
  ...
}:
{
  flake.modules.homeManager.agent-hunk =
    { lib, pkgs, ... }:
    let
      hunk = pkgs.dotfilesPackages.hunk;
    in
    {
      key = "modules/features/agents/hunk/home.nix#homeManager.agent-hunk";

      imports = [ inputs.hunk.homeManagerModules.hunk ];

      programs.hunk = {
        enable = true;
        enableGitIntegration = true;
        package = lib.mkDefault hunk.package;
        settings.wrap_lines = true;
      };
    };
}
