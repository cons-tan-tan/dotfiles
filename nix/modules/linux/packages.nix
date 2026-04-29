{ pkgs, ... }:
{
  home.packages = with pkgs; [
    drawio-headless
  ];
}
