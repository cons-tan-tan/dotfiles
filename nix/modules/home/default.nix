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

    # nixpkgs と home-manager のリリース系列不一致の警告を抑止する
    # (follows 一本化後に有効へ戻す予定: plan.md Phase 3)
    enableNixpkgsReleaseCheck = false;
  };

  programs.home-manager.enable = true;
}
