{ pkgs }:

let
  markdownlintNodePackage = pkgs.lib.importJSON ./node/package.json;

  markdownlintNodeModules = pkgs.importNpmLock.buildNodeModules {
    package = markdownlintNodePackage;
    packageLock = pkgs.lib.importJSON ./node/package-lock.json;
    inherit (pkgs) nodejs;
    derivationArgs = {
      pname = "markdownlint-node-modules";
      version = markdownlintNodePackage.version;
    };
  };
  techDocConfig = ./configs/tech-doc.markdownlint.yaml;

  runner = pkgs.writeShellScript "markdownlint-run" ''
    set -euo pipefail

    usage() {
      cat >&2 <<'EOF'
    usage: nix run dotfiles#markdownlint -- <files...>
    EOF
    }

    if [ "$#" -eq 0 ]; then
      usage
      exit 64
    fi

    case "$1" in
      -h|--help|help)
        usage
        exit 0
        ;;
    esac

    export NODE_PATH="${markdownlintNodeModules}/node_modules''${NODE_PATH:+:$NODE_PATH}"
    exec ${pkgs.nodejs}/bin/node \
      "${markdownlintNodeModules}/node_modules/markdownlint-cli/markdownlint.js" \
      --config "${techDocConfig}" \
      "$@"
  '';
in
{
  type = "app";
  meta.description = "Run markdownlint with repository-managed technical documentation modes";
  program = toString runner;
}
