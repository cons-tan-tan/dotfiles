# 外部バイナリキャッシュの接続情報。identity module が参照し、flake-file が
# flake.nix の直接 attrset へ生成する。
{
  numtideSubstituter = "https://cache.numtide.com";
  numtideTrustedPublicKey = "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=";
  nixCommunitySubstituter = "https://nix-community.cachix.org";
  nixCommunityTrustedPublicKey = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
}
