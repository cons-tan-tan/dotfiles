# numtide バイナリキャッシュの接続情報。nixConfig は直接の attrset を要求して
# import を含む let 式を受理しないため、flake.nix との同期は併置テストで保証する。
{
  numtideSubstituter = "https://cache.numtide.com";
  numtideTrustedPublicKey = "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=";
}
