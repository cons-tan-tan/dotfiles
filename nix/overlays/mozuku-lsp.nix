# MoZuKu 日本語 LSP を flake input から橋渡しする。
# input が nixpkgs を follows しない理由は flake.nix の mozuku input を参照。
{ inputs }:
_final: prev: {
  mozuku-lsp = inputs.mozuku.packages.${prev.stdenv.hostPlatform.system}.default;
}
