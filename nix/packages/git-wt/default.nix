{
  lib,
  buildGoModule,
  fetchFromGitHub,
  git,
  makeWrapper,
  pin ? builtins.fromJSON (builtins.readFile ../../pins/git-wt.json),
}:

# version / hash は nix/pins/git-wt.json に固定し、`nix run .#update-pins` で
# 自動更新する。vendorHash = "" は「未計算」の印で、lib.fakeHash に解決される
# (update-pins がビルドエラーから実 hash を取り出して埋める)。
buildGoModule rec {
  pname = "git-wt";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "k1LoW";
    repo = "git-wt";
    rev = "v${version}";
    hash = pin.srcHash;
  };

  vendorHash = if pin.vendorHash == "" then lib.fakeHash else pin.vendorHash;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ git ];

  postInstall = ''
    wrapProgram $out/bin/git-wt --prefix PATH : ${lib.makeBinPath [ git ]}
  '';

  meta = with lib; {
    description = "Simple git worktree manager";
    homepage = "https://github.com/k1LoW/git-wt";
    license = licenses.mit;
  };
}
