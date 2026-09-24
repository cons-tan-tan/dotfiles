{
  config,
  ...
}:
{
  flake.modules.homeManager.gh = { pkgs, ... }: {
    key = "modules/features/git/gh/default.nix#homeManager.gh";
    imports = [
      config.flake.modules.homeManager.git
      ({ pkgs, ... }: {
        programs.gh = {
          enable = true;
          gitCredentialHelper.enable = true;
          extensions = [
            pkgs.dotfilesPackages.gh-api-get
            pkgs.gh-do
            pkgs.gh-poi
            pkgs.gh-stack
          ];
        };
      })
    ];
    dotfiles.cliTools = [
      {
        id = "gh";
        nix.route = "programs";
        winget = {
          packageId = "GitHub.cli";
          dependsOn = [ "git" ];
          description = "GitHub CLI";
        };
      }
    ];
    dotfiles.agentCommandPolicyContributions = [
      {
        owner = "feature/gh";
        policy.commands.gh = {
          issue = {
            list = true;
            view = true;
          };
          pr = {
            list = true;
            view = true;
            diff = true;
            checks = true;
          };
          run = {
            download = true;
            list = true;
            view = true;
            watch = true;
          };
          repo = {
            clone = true;
            read-dir = true;
            read-file = true;
            view = true;
          };
          search = true;
          stack.view = true;
          api-get = true;
        };
      }
    ];
    dotfiles.agentSkillContributions = [
      {
        name = "gh-stack";
        provenance = "external";
        definition.root = "${pkgs.gh-stack}/share/skills/gh-stack/gh-stack";
      }
    ];
  };
}
