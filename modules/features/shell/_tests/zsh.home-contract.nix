{ }:
{
  describe =
    target:
    let
      config = target.config;
      inherit (target) pkgs;
      nixbuildFragments = [
        "use_nixbuild_for_ghq_owner"
        "cons-tan-tan"
        pkgs.stdenv.hostPlatform.system
        "ssh://eu.nixbuild.net"
        "builders = $host $system - $max_jobs"
        "max-jobs = 0"
      ];
      nixbuildConfigured =
        builtins.all (fragment: pkgs.lib.hasInfix fragment config.programs.direnv.stdlib) nixbuildFragments
        && !pkgs.lib.hasInfix "id_nixbuild" config.programs.direnv.stdlib;
      nixbuildStatus =
        if nixbuildConfigured then
          "configured"
        else if !pkgs.lib.hasInfix "nixbuild" config.programs.direnv.stdlib then
          "absent"
        else
          "incomplete";
    in
    {
      direnv = config.programs.direnv.enable;
      direnvNix = config.programs.direnv.nix-direnv.enable;
      direnvNixbuildPolicy = nixbuildStatus;
      direnvZsh = config.programs.direnv.enableZshIntegration;
      starship = config.programs.starship.enable;
      starshipPreset = builtins.elem "nerd-font-symbols" config.programs.starship.presets;
      starshipZsh = config.programs.starship.enableZshIntegration;
      zoxide = config.programs.zoxide.enable;
      zoxideZsh = config.programs.zoxide.enableZshIntegration;
      zsh = config.programs.zsh.enable;
    };
  expected = facts: {
    direnv = true;
    direnvNix = true;
    direnvNixbuildPolicy =
      if facts.environment == "wsl" && !facts.standalone then "configured" else "absent";
    direnvZsh = true;
    starship = true;
    starshipPreset = true;
    starshipZsh = true;
    zoxide = true;
    zoxideZsh = true;
    zsh = true;
  };
}
