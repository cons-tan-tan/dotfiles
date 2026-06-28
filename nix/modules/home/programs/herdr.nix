{ pkgs, ... }:
let
  herdrWrapped = pkgs.writeShellApplication {
    name = "herdr";
    text = ''
      needs_focus_reporting_workaround=false
      case "''${1-}" in
        ""|--session|--no-session|--remote)
          needs_focus_reporting_workaround=true
          ;;
        session)
          if [ "''${2-}" = attach ]; then
            needs_focus_reporting_workaround=true
          fi
          ;;
      esac

      # Windows Terminal 1.24 + WSL では focus reporting (?1004) が有効な
      # herdr pane へ戻ると IME が日本語入力へ切り替わらなくなることがある。
      # 他の terminal では herdr の focus tracking を維持したいので、
      # Windows Terminal 上の WSL にだけ workaround を限定する。
      if [ "$needs_focus_reporting_workaround" = true ] \
        && [ -n "''${WT_SESSION:-}" ] \
        && [ -n "''${WSL_DISTRO_NAME:-}" ] \
        && [ -t 1 ]; then
        (
          sleep 1
          printf '\033[?1004l' > /dev/tty 2>/dev/null || true
        ) &
      fi

      exec ${pkgs.herdr}/bin/herdr "$@"
    '';
  };

  tomlFormat = pkgs.formats.toml { };
  configFile = tomlFormat.generate "herdr-config.toml" {
    onboarding = false;

    keys = {
      prefix = "ctrl+a";
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
