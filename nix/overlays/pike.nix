final: prev: {
  pike = prev.stdenv.mkDerivation rec {
    pname = "pike";
    version = "0.3.85";

    src = prev.fetchurl {
      url = "https://github.com/JamesWoolfenden/pike/releases/download/v${version}/pike_${version}_linux_amd64.tar.gz";
      hash = "sha256-jvvLAtT72KqsDH562sDNmmlMkZPqSIEeN2NdcAFPszg=";
    };

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      install -m755 pike $out/bin/pike
      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "Pike is a tool for determining the permissions or policy required for IAC code";
      homepage = "https://github.com/JamesWoolfenden/pike";
      license = licenses.asl20;
      maintainers = [ ];
      mainProgram = "pike";
      platforms = [ "x86_64-linux" ];
    };
  };
}
