{ inputs }:
system:
let
  isDarwin = builtins.match ".*-darwin" system != null;
in
import inputs.nixpkgs {
  inherit system;
  config.allowUnfree = true;
  overlays = [
    (final: prev: {
      _llm-agents = inputs.llm-agents;
      mozuku-lsp = inputs.mozuku.packages.${system}.default;
    })
    (import ../overlays)
  ]
  ++ inputs.nixpkgs.lib.optionals isDarwin [
    inputs.brew-nix.overlays.default
  ];
}
