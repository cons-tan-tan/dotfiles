# darwin / linux 共通の flake apps。ホスト固有の build / switch / winget-apply
# は flake.nix 側で合成する。
{ inputs }:
{
  pkgs,
  treefmtWrapper,
}:
{
  update = {
    type = "app";
    meta.description = "Update flake.lock to the latest input revisions";
    program = toString (
      pkgs.writeShellScript "flake-update" ''
        set -e
        echo "Updating flake.lock..."
        nix flake update
        echo "Done! Run 'nix run .#switch' to apply changes."
      ''
    );
  };

  fmt = {
    type = "app";
    meta.description = "Format the repository with treefmt";
    program = toString (
      pkgs.writeShellScript "treefmt-wrapper" ''
        exec ${treefmtWrapper}/bin/treefmt "$@"
      ''
    );
  };

  pptx = import ../apps/pptx {
    inherit pkgs;
    inherit (inputs)
      anthropic-skills
      pyproject-build-systems
      pyproject-nix
      uv2nix
      ;
  };

  markdownlint = import ../apps/markdownlint { inherit pkgs; };

  textlint = import ../apps/textlint { inherit pkgs; };
}
