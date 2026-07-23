{
  lib,
  stdenvNoCC,
  fetchPnpmDeps,
  fetchurl,
  makeWrapper,
  nodejs_24,
  pnpm_11,
  pnpmConfigHook,
  difitSource,
  difitPin ? builtins.fromJSON (builtins.readFile ../../pins/difit.json),
}:
let
  pin = difitPin;
  upstreamManifest = builtins.fromJSON (builtins.readFile "${difitSource}/package.json");
  version = upstreamManifest.version;
  # npm tarballのbuild済みdistを使い、依存graphだけは同じtagで上流が検証した
  # pnpm lockから再現する。両derivationで同じmetadataを重ねる必要がある。
  copyUpstreamPnpmMetadata = ''
    cp ${difitSource}/pnpm-lock.yaml pnpm-lock.yaml
    cp ${difitSource}/pnpm-workspace.yaml pnpm-workspace.yaml
  '';
in
assert lib.assertMsg (
  upstreamManifest.name == "difit"
) "difit-src package.json must describe the difit package";
assert lib.assertMsg (lib.hasPrefix "pnpm@11." (
  upstreamManifest.packageManager or ""
)) "difit-src package.json must declare pnpm major version 11";
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "difit";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/difit/-/difit-${version}.tgz";
    hash = pin.srcHash;
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      pnpmInstallFlags
      pnpmWorkspaces
      ;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = pin.pnpmDepsHash;
    postPatch = copyUpstreamPnpmMetadata;
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs_24
    pnpm_11
    pnpmConfigHook
  ];

  postPatch = copyUpstreamPnpmMetadata;
  pnpmInstallFlags = [ "--prod" ];
  pnpmWorkspaces = [ "difit" ];
  dontBuild = true;

  preConfigure = ''
    DIFIT_EXPECTED_VERSION=${lib.escapeShellArg version} \
      ${lib.getExe nodejs_24} --input-type=module --eval '
        import fs from "node:fs";
        const manifest = JSON.parse(fs.readFileSync("package.json", "utf8"));
        if (manifest.name !== "difit" || manifest.version !== process.env.DIFIT_EXPECTED_VERSION) {
          throw new Error(`unexpected npm artifact identity: ''${manifest.name}@''${manifest.version}`);
        }
      '
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/lib/difit"
    cp -r dist node_modules package.json "$out/lib/difit/"
    makeWrapper ${lib.getExe nodejs_24} "$out/bin/difit" \
      --inherit-argv0 \
      --add-flags "$out/lib/difit/dist/cli/index.js"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test "$("$out/bin/difit" --version)" = "${version}"
    "$out/bin/difit" --help >/dev/null
    (
      cd "$out/lib/difit"
      ${lib.getExe nodejs_24} --input-type=module --eval \
        'const watcher = await import("@parcel/watcher"); if (typeof watcher.subscribe !== "function") process.exit(1)'
    )

    runHook postInstallCheck
  '';

  passthru.updatePinsDependencyProvenance = {
    kind = "upstream-pnpm";
    lockPath = "pnpm-lock.yaml";
    workspacePath = "pnpm-workspace.yaml";
    workspace = "difit";
    pnpmMajor = 11;
    scope = "production";
  };

  meta = {
    description = "GitHub-style local Git diff viewer for code review";
    homepage = "https://github.com/yoshiko-pg/difit";
    license = lib.licenses.mit;
    mainProgram = "difit";
    # @parcel/watcherはlocal fallbackをbuildしないため、検証済みprebuildがある
    # このflakeの対象systemだけを公開する。
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
