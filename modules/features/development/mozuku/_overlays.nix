# MoZuKu 日本語 LSP を flake input から橋渡しする。
{ inputs }:
_final: prev: {
  mozuku-lsp = inputs.mozuku.packages.${prev.stdenv.hostPlatform.system}.default;
}
