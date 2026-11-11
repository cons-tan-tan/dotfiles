_: {
  flake.modules.homeManager.agent-modern-web-guidance = {
    key = "modules/features/agents/modern-web-guidance/default.nix#homeManager.agent-modern-web-guidance";
    imports = [
      (
        { pkgs, ... }:
        let
          package = pkgs.dotfilesPackages.modern-web-guidance;
        in
        {
          home.packages = [ package ];
          dotfiles.agentSkillContributions = [
            {
              name = "modern-web-guidance";
              provenance = "external";
              definition = {
                root = package.skillRoot;
                customization.body.program = ./_lib/transform-skill.nix;
              };
            }
          ];
        }
      )
    ];
  };
}
