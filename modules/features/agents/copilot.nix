{ ... }:
{
  flake.modules.homeManager.agent-copilot = {
    key = "modules/features/agents/copilot.nix#homeManager.agent-copilot";
    imports = [
      (
        { pkgs, ... }:
        {
          home.packages = [ pkgs.github-copilot-cli ];
        }
      )
    ];
    dotfiles.unfreePackages = [ "github-copilot-cli" ];
  };
}
