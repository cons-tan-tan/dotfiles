{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
  unzip,
}:
let
  release =
    if stdenv.hostPlatform.isx86_64 then
      {
        arch = "x86_64";
        linuxHash = "sha256-2BxY3jev499tOLWvsEKTRyTnLsUf+4dAAhq+00UTSMw=";
        windowsHash = "sha256-G31FLy3kYqVpxAhB7mCAeC402jgVzKhCxQtCeGV8jw4=";
      }
    else if stdenv.hostPlatform.isAarch64 then
      {
        arch = "aarch64";
        linuxHash = "sha256-TwnIwYAhNG7JVj4AwV+JXBflFo5GIYRH7402FlZQvmw=";
        windowsHash = "sha256-lNLVWHSccyEDuP5qvP6RYzfvXoCtyhZuK0HbSo4EtgU=";
      }
    else
      throw "sshenc: unsupported Linux architecture ${stdenv.hostPlatform.system}";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "sshenc";
  version = "0.6.101";

  src = fetchurl {
    url = "https://github.com/GoDaddy/sshenc/releases/download/v${finalAttrs.version}/sshenc-${release.arch}-unknown-linux-gnu.tar.gz";
    hash = release.linuxHash;
  };
  bridgeSrc = fetchurl {
    url = "https://github.com/GoDaddy/sshenc/releases/download/v${finalAttrs.version}/sshenc-${release.arch}-pc-windows-msvc.zip";
    hash = release.windowsHash;
  };

  sourceRoot = ".";
  dontBuild = true;
  nativeBuildInputs = [
    autoPatchelfHook
    unzip
  ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall

    install -Dm755 sshenc sshenc-agent -t "$out/bin"
    unzip -j "$bridgeSrc" sshenc-tpm-bridge.exe -d "$out/bin"
    chmod 0755 "$out/bin/sshenc-tpm-bridge.exe"

    runHook postInstall
  '';

  meta = {
    description = "Hardware-backed SSH and Git signing client";
    homepage = "https://github.com/GoDaddy/sshenc";
    license = lib.licenses.mit;
    mainProgram = "sshenc";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
