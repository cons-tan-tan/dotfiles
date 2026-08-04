{ den, ... }:
{
  den.aspects.development-shells.devShells =
    { pkgs, ... }:
    {
      default = pkgs.mkShell {
        packages = with pkgs; [
          bats
          git
          jq
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

  den.schema.flake-parts.includes = [ den.aspects.development-shells ];
}
