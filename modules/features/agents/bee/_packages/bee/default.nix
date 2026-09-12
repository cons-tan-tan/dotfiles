{
  callPackage,
  importNpmLock,
  lib,
  makeWrapper,
  nodejs_24,
  stdenvNoCC,
}:
let
  manifest = lib.importJSON ./node/package.json;
  lock = lib.importJSON ./node/package-lock.json;
  version = manifest.dependencies."@nulab/bee";
  nodeModules = importNpmLock.buildNodeModules {
    package = manifest;
    packageLock = lock;
    nodejs = nodejs_24;
    derivationArgs = {
      pname = "bee-node-modules";
      inherit version;
    };
  };
  updater = callPackage ../../_scripts/update.nix { };
in
assert lib.assertMsg (
  lock.packages."node_modules/@nulab/bee".version == version
) "bee package.json and package-lock.json must pin the same release";
stdenvNoCC.mkDerivation {
  pname = "bee";
  inherit version;
  dontUnpack = true;
  dontBuild = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    makeWrapper ${lib.getExe nodejs_24} "$out/bin/bee" \
      --inherit-argv0 \
      --add-flags "${nodeModules}/node_modules/@nulab/bee/bin/cli.mjs"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/bee" --version)" = "${version}"
    # Subcommand help also loads the published command chunks, without auth.
    "$out/bin/bee" wiki view --help > /dev/null
    help=$("$out/bin/bee" wiki edit --help)
    [[ "$help" == *'echo "New content" | bee wiki edit 12345'* ]]
    runHook postInstallCheck
  '';

  passthru = {
    updateScript = lib.getExe updater;
    updateScriptName = "bee";
    updateScriptDescription = "Update bee npm dependencies and its paired skills input";
  };

  meta = {
    description = "Command-line tool to view and manage Backlog";
    homepage = "https://github.com/nulab/bee";
    changelog = "https://github.com/nulab/bee/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "bee";
    platforms = lib.platforms.unix;
  };
}
