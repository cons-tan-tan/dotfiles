{ pkgs, ... }:
{
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty-bin;
    settings = {
      background-opacity = 0.7;
      font-family = "HackGen Console NF";
    };
  };
}
