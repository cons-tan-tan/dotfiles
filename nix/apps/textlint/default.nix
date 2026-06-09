{ pkgs }:

let
  textlintNodePackage = pkgs.lib.importJSON ./node/package.json;

  textlintNodeModules = pkgs.importNpmLock.buildNodeModules {
    package = textlintNodePackage;
    packageLock = pkgs.lib.importJSON ./node/package-lock.json;
    inherit (pkgs) nodejs;
    derivationArgs = {
      pname = "textlint-node-modules";
      version = textlintNodePackage.version;
    };
  };
  techJpConfig = ./configs/tech-jp.textlintrc.yaml;

  runner = pkgs.writeShellScript "textlint-run" ''
    set -euo pipefail

    usage() {
      cat >&2 <<'EOF'
    usage: nix run dotfiles#textlint -- tech-jp <files...>

    modes:
      tech-jp  Lint Japanese technical documentation with textlint.
    EOF
    }

    if [ "$#" -eq 0 ]; then
      usage
      exit 64
    fi

    mode="$1"
    shift

    case "$mode" in
      tech-jp)
        config="${techJpConfig}"
        ;;
      -h|--help|help)
        usage
        exit 0
        ;;
      *)
        echo "textlint: unknown mode: $mode" >&2
        usage
        exit 64
        ;;
    esac

    if [ "$#" -eq 0 ]; then
      usage
      exit 64
    fi

    export NODE_PATH="${textlintNodeModules}/node_modules''${NODE_PATH:+:$NODE_PATH}"
    exec ${pkgs.nodejs}/bin/node \
      "${textlintNodeModules}/node_modules/textlint/bin/textlint.js" \
      --config "$config" \
      "$@"
  '';
in
{
  type = "app";
  meta.description = "Run textlint with repository-managed Japanese documentation lint modes";
  program = toString runner;
}
