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
    (final: prev: {
      mozuku-lsp = inputs.mozuku.packages.${system}.default;
    })
    (import ../overlays/llm-agents.nix inputs.llm-agents)
    (import ../overlays/git-wt.nix)
    (import ../overlays/agent-slack.nix)
    (import ../overlays/difit.nix)
    (import ../overlays/hcom.nix)
    (import ../overlays/shellfirm.nix)
  ]
  ++ lib.optionals (!isDarwin) [
    # xvfb-run / dbus 依存のため Linux 系のみ
    (import ../overlays/drawio-headless.nix)
  ]
  ++ lib.optionals isDarwin [
    inputs.brew-nix.overlays.default
  ];
}
