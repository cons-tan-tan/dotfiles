final: prev: {
  git-wt = prev.buildGoModule rec {
    pname = "git-wt";
    version = "0.15.0";

    src = prev.fetchFromGitHub {
      owner = "k1LoW";
      repo = "git-wt";
      rev = "v${version}";
      hash = "sha256-A8vkwa8+RfupP9UaUuSVjkt5HtWvqR5VmSsVg2KpeMo=";
    };

    vendorHash = "sha256-K5geAvG+mvnKeixOyZt0C1T5ojSBFmx2K/Msol0HsSg=";

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
