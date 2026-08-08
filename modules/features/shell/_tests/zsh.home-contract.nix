{ }:
{
  describe =
    target:
    let
      config = target.config;
    in
    {
      direnv = config.programs.direnv.enable;
      direnvInstant = config.programs.direnv-instant.enable;
      direnvInstantCache = config.programs.direnv-instant.settings.use_cache;
      direnvNix = config.programs.direnv.nix-direnv.enable;
      direnvZsh = config.programs.direnv.enableZshIntegration;
      starship = config.programs.starship.enable;
      starshipPreset = builtins.elem "nerd-font-symbols" config.programs.starship.presets;
      starshipZsh = config.programs.starship.enableZshIntegration;
      zoxide = config.programs.zoxide.enable;
      zoxideZsh = config.programs.zoxide.enableZshIntegration;
      zsh = config.programs.zsh.enable;
    };
  expected = _: {
    direnv = true;
    direnvInstant = true;
    direnvInstantCache = true;
    direnvNix = true;
    direnvZsh = false;
    starship = true;
    starshipPreset = true;
    starshipZsh = true;
    zoxide = true;
    zoxideZsh = true;
    zsh = true;
  };
}
