{
  # mozuku-lsp は cabocha / crfpp の C++ チェーンごと source build になり、
  # binary cache にない。nixpkgs を follows するとその更新ごとに再ビルド
  # されるため、upstream の pin を version authority とする。
  flake-file.inputs.mozuku.url = "github:t3tra-dev/MoZuKu";
}
