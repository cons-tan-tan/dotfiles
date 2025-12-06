{ pkgs, ... }:
{
  programs.starship = {
    enable = true;
    settings = {
      python = {
        detect_extensions = [ ];
        detect_files = [ ];
      };
    };
  };
}
