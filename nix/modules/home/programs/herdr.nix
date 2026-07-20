{ pkgs, ... }:
let
  tomlFormat = pkgs.formats.toml { };
  configFile = tomlFormat.generate "herdr-config.toml" {
    onboarding = false;

    keys = {
      prefix = "ctrl+a";
    };

    ui = {
      prompt_new_tab_name = false;
    };

    experimental = {
      kitty_graphics = true;
    };

    # Codex の native session restore はこの gate が開いている時だけ走る。
    session = {
      resume_agents_on_restore = true;
    };
  };
in
{
  home.packages = [ pkgs.dotfilesPackages.herdr.wrappedPackage ];

  home.file.".config/herdr/config.toml".source = configFile;
}
