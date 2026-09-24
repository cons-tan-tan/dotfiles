{
  perSystem =
    { pkgs, ... }:
    let
      nixMutationTest = pkgs.callPackage ./_packages/nix-mutation-test { };
    in
    {
      devShells = {
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
    };
}
