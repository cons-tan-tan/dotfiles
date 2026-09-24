_: {
  flake.modules.homeManager.platform-ghostty = { pkgs, ... }: {
    key = "modules/features/platform/darwin/ghostty.nix#homeManager.platform-ghostty";

    programs.ghostty = {
      enable = true;
      package = pkgs.ghostty-bin;
      settings = {
        background-opacity = 0.7;
        font-family = [
          "HackGen Console NF"
          "Symbols Nerd Font Mono"
        ];
      };
    };
  };
}
