{
  flake.modules.homeManager.agent-gemini =
    { pkgs, ... }:
    {
      key = "modules/features/agents/gemini.nix#homeManager.agent-gemini";

      home.packages = [ pkgs.gemini-cli ];
    };
}
