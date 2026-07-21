{ inputs }:
system:
let
  inherit (inputs.nixpkgs) lib;
  isDarwin = lib.hasSuffix "-darwin" system;
in
import inputs.nixpkgs {
  inherit system;
  config.allowUnfree = true;
  overlays = [
    (import ../overlays/mozuku-lsp.nix { inherit inputs; })
    (import ../overlays/llm-agents.nix inputs.llm-agents)
    (import ../overlays/local-packages.nix {
      inherit inputs;
    })
  ]
  ++ lib.optionals isDarwin [
    (import ../overlays/watchexec.nix { })
    inputs.brew-nix.overlays.default
  ];
}
