{ inputs, ... }:
{
  # CLI pin と agent skill source は update-pins が同じ release へ揃える。
  flake-file.inputs.difit-src = {
    url = "github:yoshiko-pg/difit/v5.0.8";
    flake = false;
  };

  features.agent-difit = {
    name = "feature/agents/difit";
    agent-skills = [
      {
        name = "difit";
        provenance = "external";
        definition = {
          root = inputs.difit-src.outPath + "/skills/difit";
          customization.disableAutomaticInvocation = true;
        };
      }
      {
        name = "difit-review";
        provenance = "external";
        definition = {
          root = inputs.difit-src.outPath + "/skills/difit-review";
          customization.disableAutomaticInvocation = true;
        };
      }
    ];
    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.dotfilesPackages.difit ];
    };
  };
}
