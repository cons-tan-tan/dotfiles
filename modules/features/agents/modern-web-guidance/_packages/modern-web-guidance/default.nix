{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  nodejs,
  nix-update-script,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "modern-web-guidance";
  version = "1.0.0";

  # The npm archive bundles the CLI, search data, guides, and matching skill.
  # Keeping one source avoids independently updated skill-version identifiers.
  src = fetchurl {
    url = "https://registry.npmjs.org/modern-web-guidance/-/modern-web-guidance-${finalAttrs.version}.tgz";
    hash = "sha256-vXqmI60QcQqa1meP28wLiQyQPFT9ar/BJv9C3gHw5Xc=";
  };

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  postPatch = ''
    ${lib.getExe nodejs} ${./rewrite-references.mjs} skills/modern-web-guidance
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/libexec/modern-web-guidance" "$out/bin"
    cp -R . "$out/libexec/modern-web-guidance/"
    makeWrapper ${lib.getExe nodejs} "$out/bin/modern-web-guidance" \
      --add-flags "$out/libexec/modern-web-guidance/skills/modern-web-guidance/modern-web.mjs"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${lib.getExe nodejs} ${../../_tests/check-package.mjs} \
      "$out/bin/modern-web-guidance" \
      "$out/libexec/modern-web-guidance/skills/modern-web-guidance" \
      ${lib.escapeShellArg finalAttrs.version}
    runHook postInstallCheck
  '';

  passthru = {
    skillRoot = "${finalAttrs.finalPackage}/libexec/modern-web-guidance/skills/modern-web-guidance";
    updateScript = nix-update-script {
      attrPath = "modern-web-guidance";
      extraArgs = [
        "--file"
        "modules/features/nixpkgs/_interface/nix-update-package-set.nix"
      ];
    };
    updateScriptName = "modern-web-guidance";
    updateScriptDescription = "Update Modern Web Guidance CLI, guides, and skill together";
  };

  meta = {
    description = "Modern web platform guidance for coding agents";
    homepage = "https://github.com/GoogleChrome/modern-web-guidance";
    license = with lib.licenses; [
      asl20
      cc-by-40
    ];
    platforms = lib.platforms.unix;
    mainProgram = "modern-web-guidance";
  };
})
