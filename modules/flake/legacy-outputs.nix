{ inputs, withSystem, ... }:
{
  flake = import ../_legacy/outputs.nix (
    inputs
    // {
      appScriptsFor = system: withSystem system ({ config, ... }: config.dotfiles.appScripts);
    }
  );
}
