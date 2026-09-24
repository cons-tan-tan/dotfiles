{ inputs, ... }:
{
  # Named modules wrap their fragments anonymously. Feature fragments supply a
  # source-specific Nix module key so shared imports apply once; contributors
  # to the same named module must keep distinct keys.
  # https://github.com/hercules-ci/flake-parts/issues/299
  imports = [ inputs.flake-file.flakeModules.dendritic ];
}
