{ pkgs, lib, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;

  wsl-open-bin = pkgs.writeShellApplication {
    name = "wsl-open";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      if [[ -z "''${WSL_DISTRO_NAME:-}" ]]; then
        echo "wsl-open: not running under WSL" >&2
        exit 1
      fi

      if [[ $# -ne 1 ]]; then
        echo "Usage: wsl-open URL_OR_PATH" >&2
        exit 1
      fi

      target="$1"
      case "$target" in
        *://*|mailto:*) ;;
        *)
          target=$(wslpath -w "$(realpath -- "$target")")
          ;;
      esac

      exec /mnt/c/Windows/System32/rundll32.exe url.dll,FileProtocolHandler "$target"
    '';
  };

  wsl-open = pkgs.symlinkJoin {
    name = "wsl-open";
    paths = [ wsl-open-bin ];
    postBuild = ''
      ln -s wsl-open "$out/bin/x-www-browser"
    '';
  };
in
{
  home.packages = lib.optionals (!isDarwin) [ wsl-open ];

  home.sessionVariables = lib.optionalAttrs (!isDarwin) {
    BROWSER = "wsl-open";
  };
}
