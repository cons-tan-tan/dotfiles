final: prev:
let
  # version / hash は nix/pins/git-wt.json に固定し、`nix run .#update-pins` で
  # 自動更新する。vendorHash = "" は「未計算」の印で、lib.fakeHash に解決される
  # (update-pins がビルドエラーから実 hash を取り出して埋める)。
  pin = builtins.fromJSON (builtins.readFile ../pins/git-wt.json);
in
{
  git-wt = prev.buildGoModule rec {
    pname = "git-wt";
    inherit (pin) version;

    src = prev.fetchFromGitHub {
      owner = "k1LoW";
      repo = "git-wt";
      rev = "v${version}";
      hash = pin.srcHash;
    };

    vendorHash = if pin.vendorHash == "" then prev.lib.fakeHash else pin.vendorHash;

    nativeBuildInputs = [ prev.makeWrapper ];
    nativeCheckInputs = [ prev.git ];

    postInstall = ''
      wrapProgram $out/bin/git-wt --prefix PATH : ${prev.lib.makeBinPath [ prev.git ]}
    '';

    meta = with prev.lib; {
      description = "Simple git worktree manager";
      homepage = "https://github.com/k1LoW/git-wt";
      license = licenses.mit;
    };
  };
}
