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
    (import ../overlays/llm-agents.nix {
      inherit (inputs) llm-agents agent-browser-skill;
    })
    (import ../overlays/agent-slack.nix inputs.agent-slack-skill)
    (import ../overlays/difit.nix inputs.difit-src)
    (import ../overlays/hcom.nix inputs.hcom-src)
    (import ../overlays/hunk.nix inputs.hunk)
    (import ../overlays/shellfirm.nix)
  ]
  ++ lib.optionals (!isDarwin) [
    # xvfb-run / dbus 依存のため Linux 系のみ
    (import ../overlays/drawio-headless.nix)
  ]
  ++ lib.optionals isDarwin [
    (import ../overlays/codex-app.nix)
    (import ../overlays/watchexec.nix)
    inputs.brew-nix.overlays.default
  ];
}
