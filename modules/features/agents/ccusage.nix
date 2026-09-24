{
  flake.modules.homeManager.agent-ccusage =
    { pkgs, ... }:
    {
      key = "modules/features/agents/ccusage.nix#homeManager.agent-ccusage";

      home.packages = [ pkgs.ccusage ];
    };
}
