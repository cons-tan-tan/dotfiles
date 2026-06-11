{ pkgs }:

let
  nodeLint = import ../mk-node-lint-app.nix { inherit pkgs; } {
    name = "markdownlint";
    nodeDir = ./node;
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

    ${nodeLint.mkExec "markdownlint-cli/markdownlint.js"} \
      --config "${techDocConfig}" \
      "$@"
  '';
in
{
  type = "app";
  meta.description = "Run markdownlint with repository-managed technical documentation modes";
  program = toString runner;
}
