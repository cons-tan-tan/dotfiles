{ ... }:
{
  imports = [
    ./agent-skills.nix
    ./packages.nix
    ./programs
    ./registries.nix
  ];

  home = {
    stateVersion = "24.11";

    # home-manager / nixpkgs とも unstable 系列を follows で一本化しているので
    # リリース不一致チェックは有効のままにできる (デフォルト true を明示)。
    enableNixpkgsReleaseCheck = true;
  };

  programs.home-manager.enable = true;
}
