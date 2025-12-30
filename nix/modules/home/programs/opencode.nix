{ pkgs, ... }:
{
  programs.opencode = {
    enable = true;
    settings = {
      theme = "transparent";
    };
    themes = {
      transparent = {
        defs = { };
        theme = {
          # Required fields
          primary = "#88C0D0";
          secondary = "#81A1C1";
          accent = "#8FBCBB";
          text = "#ECEFF4";
          textMuted = "#b7b9be";
          background = "none";
          backgroundPanel = "none";
          backgroundElement = "none";
        };
      };
    };
  };
}
