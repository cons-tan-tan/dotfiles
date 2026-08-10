{
  callPackage,
  cargo-about,
  cargo-deny,
  jq,
  lib,
  makeWrapper,
  nodejs_24,
  rustPlatform,
}:
let
  manifest = fromTOML (builtins.readFile ./Cargo.toml);
  languageServer = builtins.fromJSON (builtins.readFile ./language-server.json);
  nodeLicenseInventory = builtins.fromJSON (builtins.readFile ./vendor/third-party-licenses.json);
  updater = callPackage ../../_scripts/update-gha-diag.nix { };
in
assert languageServer.bundleReproduction.byteForByte;
assert languageServer.registryVerification.sourceDependencies;
assert languageServer.registryVerification.reproductionDependencies;
assert nodeLicenseInventory.schemaVersion == "gha-diag-node-licenses-v2";
assert nodeLicenseInventory.upstreamRevision == languageServer.gitHead;
assert nodeLicenseInventory.packageLockSha256 == languageServer.upstreamPackageLockSha256;
assert nodeLicenseInventory.bundleSha256 == languageServer.bundleSha256;
assert
  nodeLicenseInventory.reproduction.esbuildVersion
  == languageServer.bundleReproduction.esbuildVersion;
assert nodeLicenseInventory.packages != [ ];
rustPlatform.buildRustPackage {
  pname = manifest.package.name;
  inherit (manifest.package) version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./about.hbs
      ./about.toml
      ./deny.toml
      ./src
      ./tests
      ./language-server.json
      ./vendor
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [
    cargo-about
    makeWrapper
  ];
  nativeCheckInputs = [
    cargo-deny
    jq
    nodejs_24
  ];
  GHA_DIAG_TEST_NODE = lib.getExe nodejs_24;
  cargoTestFlags = [ "--all-targets" ];

  postBuild = ''
    cargo-about generate \
      --config ./about.toml \
      --manifest-path ./Cargo.toml \
      --frozen \
      --fail \
      --output-file generated-LICENSE-RUST-THIRD-PARTY \
      ./about.hbs
  '';

  postCheck = ''
    cargo-deny \
      --config ./deny.toml \
      --manifest-path ./Cargo.toml \
      --offline \
      --locked \
      check licenses
  '';

  postInstall = ''
    wrapProgram "$out/bin/gha-diag" \
      --set-default GHA_DIAG_NODE ${lib.getExe nodejs_24}

    install -Dm644 ${./language-server.json} \
      "$out/share/gha-diag/language-server.json"
    install -Dm644 ${./vendor/LICENSE} \
      "$out/share/licenses/gha-diag/actions-languageserver-LICENSE"
    install -Dm644 ${./vendor/LICENSE-THIRD-PARTY} \
      "$out/share/licenses/gha-diag/actions-languageserver-LICENSE-THIRD-PARTY"
    install -Dm644 ${./vendor/third-party-licenses.json} \
      "$out/share/licenses/gha-diag/actions-languageserver-third-party-licenses.json"
    install -Dm644 generated-LICENSE-RUST-THIRD-PARTY \
      "$out/share/licenses/gha-diag/LICENSE-RUST-THIRD-PARTY"
    install -Dm644 ${../../../../../LICENSE} \
      "$out/share/licenses/gha-diag/gha-diag-LICENSE-CC0-1.0"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    "$out/bin/gha-diag" --help >/dev/null
    "$out/bin/gha-diag" --version | grep -Fx 'gha-diag ${manifest.package.version}'
    "$out/bin/gha-diag" --version | grep -Fx '@actions/languageserver ${languageServer.version}'
    "$out/bin/gha-diag" features --format json > features.json
    grep -F '"schemaVersion": "gha-diag-features-v1"' features.json
    ${lib.getExe jq} -e \
      --argjson expected '${builtins.toJSON languageServer.experimentalFeatures}' \
      '[.features[] | select(.enabled) | .name] == $expected and
       ([.features[] | select(.overridden)] | length == 0)' \
      features.json >/dev/null
    (
      cd tests/fixtures
      "$out/bin/gha-diag" valid.yaml
      "$out/bin/gha-diag" action.yml
    )
    set +e
    (
      cd tests/fixtures
      "$out/bin/gha-diag" --format json invalid.yaml > report.json
    )
    status=$?
    set -e
    test "$status" -eq 1
    grep -F '"schemaVersion": "gha-diag-report-v1"' tests/fixtures/report.json
    grep -F '"failureThreshold": "error"' tests/fixtures/report.json
    grep -F '"conclusion": "failure"' tests/fixtures/report.json
    grep -F '"exitCode": 1' tests/fixtures/report.json
    cmp ${./vendor/LICENSE} \
      "$out/share/licenses/gha-diag/actions-languageserver-LICENSE"
    cmp ${./vendor/LICENSE-THIRD-PARTY} \
      "$out/share/licenses/gha-diag/actions-languageserver-LICENSE-THIRD-PARTY"
    cmp ${./vendor/third-party-licenses.json} \
      "$out/share/licenses/gha-diag/actions-languageserver-third-party-licenses.json"
    cmp generated-LICENSE-RUST-THIRD-PARTY \
      "$out/share/licenses/gha-diag/LICENSE-RUST-THIRD-PARTY"
    cmp ${../../../../../LICENSE} \
      "$out/share/licenses/gha-diag/gha-diag-LICENSE-CC0-1.0"
    test "$(sha256sum "$out/share/licenses/gha-diag/actions-languageserver-LICENSE-THIRD-PARTY" | cut -d ' ' -f 1)" = \
      '${languageServer.nodeLicensesSha256}'
    test "$(sha256sum "$out/share/licenses/gha-diag/actions-languageserver-third-party-licenses.json" | cut -d ' ' -f 1)" = \
      '${languageServer.nodeLicensesInventorySha256}'
    test "$(sha256sum ${./vendor/cli.bundle.cjs} | cut -d ' ' -f 1)" = \
      '${languageServer.bundleSha256}'

    runHook postInstallCheck
  '';

  passthru = {
    updateScript = lib.getExe updater;
    updateScriptName = "gha-diag";
    updateScriptDescription = "Update the bundled GitHub Actions language server";
  };

  meta = {
    description = manifest.package.description;
    homepage = "https://github.com/cons-tan-tan/dotfiles";
    license = [
      lib.licenses.cc0
      lib.licenses.mit
      lib.licenses.isc
      lib.licenses.asl20
      lib.licenses.unicode-30
    ];
    mainProgram = "gha-diag";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
