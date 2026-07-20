{ pkgs, ... }:
let
  herdrWrapped = pkgs.writeShellApplication {
    name = "herdr";
    text = ''
      export HERDR_BIN=${pkgs.dotfilesPackages.herdr}/bin/herdr
      ${builtins.readFile ./herdr-wrapper.sh}
    '';
  };

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
  home.packages = [ herdrWrapped ];

  home.file.".config/herdr/config.toml".source = configFile;
}
