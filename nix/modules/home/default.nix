{ inputs, ... }:
let
  withInputs =
    path:
    {
      config,
      lib,
      pkgs,
      ...
    }:
    import path {
      inherit
        config
        inputs
        lib
        pkgs
        ;
    };
in
{
  imports = [
    inputs.nix-index-database.homeModules.default
    ./agent-guidance
    (withInputs ./agent-skills)
    ./hcom.nix
    (withInputs ./packages.nix)
    (withInputs ./programs)
    ./registries.nix
    ./trash.nix
  ];

  home = {
    stateVersion = "24.11";

    # home-manager / nixpkgs とも unstable 系列を follows で一本化しているので
    # リリース不一致チェックは有効のままにできる (デフォルト true を明示)。
    enableNixpkgsReleaseCheck = true;
  };

  programs.home-manager.enable = true;
  programs.nix-index-database.comma.enable = true;
}
