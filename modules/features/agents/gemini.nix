{
  features.agent-gemini = {
    name = "feature/agents/gemini";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.gemini-cli ];
      };
  };
}
