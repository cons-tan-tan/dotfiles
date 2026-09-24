{ inputs, ... }:
{
  # CLI pin と agent skill source は package-owned updateScript が揃える。
  flake-file.inputs.difit-src = {
    url = "github:yoshiko-pg/difit/v5.0.8";
    flake = false;
  };

  flake.modules.homeManager.agent-difit = {
    key = "modules/features/agents/difit/default.nix#homeManager.agent-difit";
    imports = [
      ({ pkgs, ... }: {
        home.packages = [ pkgs.dotfilesPackages.difit ];
      })
    ];
    dotfiles.agentSkillContributions = [
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
  };
}
