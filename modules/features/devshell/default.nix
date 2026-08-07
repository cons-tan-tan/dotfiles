{ den, ... }:
{
  den.aspects.devshell.devShells =
    { pkgs, ... }:
    let
      nixMutationTest = pkgs.callPackage ./_packages/nix-mutation-test { };
    in
    {
      default = pkgs.mkShell {
        packages = with pkgs; [
          bats
          git
          jq
          nixMutationTest
          reuse
          shellcheck
          sops
          yq-go
        ];
      };

      rust = pkgs.mkShell {
        packages = with pkgs; [
          cargo
          clippy
          git
          rustc
          rustfmt
        ];
      };
    };

  den.schema.flake-parts.includes = [ den.aspects.devshell ];
}
