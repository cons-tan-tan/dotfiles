{ pkgs, ... }:
let
  tomlFormat = pkgs.formats.toml { };
  configFile = tomlFormat.generate "herdr-config.toml" {
    onboarding = false;

    keys = {
      prefix = "ctrl+a";
    };
  };
in
{
  home.file.".config/herdr/config.toml".source = configFile;
}
