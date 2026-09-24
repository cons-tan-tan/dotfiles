{ inputs, ... }:
{
  imports = [
    inputs.flake-file.flakeModules.dendritic
    # Named modules wrap their fragments anonymously. Feature fragments supply a
    # source-specific Nix module key so shared imports apply once; contributors
    # to the same named module must keep distinct keys.
    inputs.flake-parts.flakeModules.modules
  ];
}
