# pin ? fromJSON (readFile ...) の注入可能 default が誤って外れた時に検知する。
# 既存の herdr-package.test.nix は引数の存在だけを検査するため、default の
# 有無はここで全消費者と同じ契約として固定する。
{ lib, pkgs }:
let
  hasInjectablePin = fn: argName: (builtins.functionArgs (import fn)).${argName} or false;

  codexPin = {
    version = "99.88.77";
    appcast = "https://example.invalid/appcast.xml";
    url = "https://example.invalid/Codex.zip";
    hash = "sha256-codex-marker";
    appName = "CodexMarker.app";
    bundleIdentifier = "example.codex-marker";
    displayName = "Codex Marker";
  };

  mkCodexPackage =
    args:
    import ./codex-app (
      {
        inherit lib;
        stdenvNoCC.mkDerivation = attrs: attrs;
        fetchurl = attrs: attrs;
        unzip = "unzip";
      }
      // args
    );

  injectedCodexPackage = mkCodexPackage { pin = codexPin; };
  defaultCodexPin = lib.importJSON ../pins/codex-app.json;
  defaultCodexPackage = mkCodexPackage { };

  shellfirmPin = {
    version = "99.88.77";
    srcHash = "sha256-shellfirm-marker";
  };

  mkShellfirmPackage =
    args:
    import ./shellfirm (
      {
        inherit lib;
        rustPlatform.buildRustPackage = attrs: attrs;
        fetchFromGitHub = attrs: attrs;
        pkg-config = "pkg-config";
        openssl = "openssl";
      }
      // args
    );

  injectedShellfirmPackage = mkShellfirmPackage { pin = shellfirmPin; };
  defaultShellfirmPin = lib.importJSON ../pins/shellfirm.json;
  defaultShellfirmPackage = mkShellfirmPackage { };

  difitPin = {
    srcHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    pnpmDepsHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
  };
  injectedDifitPackage = pkgs.dotfilesPackages.difit.override { difitPin = difitPin; };
  defaultDifitPin = lib.importJSON ../pins/difit.json;
  defaultDifitPackage = pkgs.dotfilesPackages.difit;
  difitDependencyProvenance = {
    kind = "upstream-pnpm";
    lockPath = "pnpm-lock.yaml";
    workspacePath = "pnpm-workspace.yaml";
    workspace = "difit";
    pnpmMajor = 11;
    scope = "production";
  };
  mkDifitCandidate =
    expectedDependencyProvenance:
    import ../apps/update-pins/candidate-package.nix {
      inherit pkgs expectedDependencyProvenance;
      packageName = "difit";
      pinOverride = "difitPin";
      dependencyHashField = "pnpmDepsHash";
      rawPin = defaultDifitPin;
    };

  schemaPin = {
    url = "https://example.invalid/schema.json";
    hash = "sha256-schema-marker";
  };

  mkSchemaValidator =
    args:
    import ../lib/mk-claude-settings-validator.nix (
      {
        pkgs.fetchurl = attrs: attrs;
      }
      // args
    );

  injectedSchemaValidator = mkSchemaValidator { inherit schemaPin; };
  defaultSchemaPin = builtins.fromJSON (builtins.readFile ../pins/claude-code-settings-schema.json);
  defaultSchemaValidator = mkSchemaValidator { };
in
{
  testAgentBrowserPinInjectable = {
    expr = hasInjectablePin ./agent-browser/default.nix "pin";
    expected = true;
  };

  testAgentSlackPinInjectable = {
    expr = hasInjectablePin ./agent-slack/default.nix "pin";
    expected = true;
  };

  testHcomFamilyPinInjectable = {
    expr = hasInjectablePin ./hcom/default.nix "hcomPin";
    expected = true;
  };

  testHcomPackagePinInjectable = {
    expr = hasInjectablePin ./hcom/package.nix "hcomPin";
    expected = true;
  };

  testHerdrFamilyPinInjectable = {
    expr = hasInjectablePin ./herdr/default.nix "herdrPin";
    expected = true;
  };

  testHerdrPackagePinInjectable = {
    expr = hasInjectablePin ./herdr/package.nix "herdrPin";
    expected = true;
  };

  testShellfirmPinInjectable = {
    expr = hasInjectablePin ./shellfirm/default.nix "pin";
    expected = true;
  };

  testShellfirmInjectedPinPropagates = {
    expr =
      injectedShellfirmPackage.version == shellfirmPin.version
      && injectedShellfirmPackage.src.rev == "v${shellfirmPin.version}"
      && injectedShellfirmPackage.src.hash == shellfirmPin.srcHash
      && injectedShellfirmPackage.cargoLock.lockFile == ./shellfirm/Cargo.lock;
    expected = true;
  };

  testShellfirmDefaultPinPropagates = {
    expr =
      defaultShellfirmPackage.version == defaultShellfirmPin.version
      && defaultShellfirmPackage.src.rev == "v${defaultShellfirmPin.version}"
      && defaultShellfirmPackage.src.hash == defaultShellfirmPin.srcHash
      && defaultShellfirmPackage.cargoLock.lockFile == ./shellfirm/Cargo.lock;
    expected = true;
  };

  testDifitPinInjectable = {
    expr = hasInjectablePin ./difit/default.nix "difitPin";
    expected = true;
  };

  testDifitInjectedPinPropagates = {
    expr =
      injectedDifitPackage.src.outputHash == difitPin.srcHash
      && injectedDifitPackage.pnpmDeps.outputHash == difitPin.pnpmDepsHash;
    expected = true;
  };

  testDifitDefaultPinPropagates = {
    expr =
      defaultDifitPackage.src.outputHash == defaultDifitPin.srcHash
      && defaultDifitPackage.pnpmDeps.outputHash == defaultDifitPin.pnpmDepsHash;
    expected = true;
  };

  testDifitPnpmProductionScopePropagates = {
    expr =
      defaultDifitPackage.pnpmInstallFlags == [ "--prod" ]
      && defaultDifitPackage.pnpmDeps.pnpmInstallFlags == [ "--prod" ]
      && defaultDifitPackage.pnpmWorkspaces == [ "difit" ]
      && defaultDifitPackage.pnpmDeps.pnpmWorkspaces == [ "difit" ];
    expected = true;
  };

  testDifitPnpmFetcherContractPropagates = {
    expr =
      defaultDifitPackage.pnpmDeps.fetcherVersion == 4
      && lib.hasPrefix "pnpm-11." defaultDifitPackage.pnpmDeps.pnpm.name
      && defaultDifitPackage.postPatch == defaultDifitPackage.pnpmDeps.postPatch
      && lib.hasInfix "pnpm-lock.yaml" defaultDifitPackage.postPatch
      && lib.hasInfix "pnpm-workspace.yaml" defaultDifitPackage.postPatch
      && defaultDifitPackage.updatePinsDependencyProvenance == difitDependencyProvenance;
    expected = true;
  };

  testDifitPnpmToolchainPropagates = {
    expr =
      (
        !pkgs.stdenv.hostPlatform.isDarwin
        || lib.versions.major defaultDifitPackage.pnpmDeps.pnpm.nodejs-slim.version == "26"
      )
      && lib.any (
        input: (input.drvPath or null) == defaultDifitPackage.pnpmDeps.pnpm.drvPath
      ) defaultDifitPackage.nativeBuildInputs;
    expected = true;
  };

  testDifitCandidateAcceptsMatchingProvenance = {
    expr =
      let
        candidate = mkDifitCandidate difitDependencyProvenance;
      in
      candidate.src.outputHash == defaultDifitPin.srcHash
      && candidate.pnpmDeps.outputHash == lib.fakeHash;
    expected = true;
  };

  testDifitCandidateRejectsMismatchedProvenance = {
    expr =
      (builtins.tryEval ((mkDifitCandidate (difitDependencyProvenance // { pnpmMajor = 10; })).drvPath))
      .success;
    expected = false;
  };

  testWatchexecPinInjectable = {
    expr = hasInjectablePin ../overlays/watchexec.nix "pin";
    expected = true;
  };

  testCodexAppPinInjectable = {
    expr = hasInjectablePin ./codex-app/default.nix "pin";
    expected = true;
  };

  testCodexAppInjectedPinPropagates = {
    expr =
      injectedCodexPackage.version == codexPin.version
      && injectedCodexPackage.src.url == codexPin.url
      && injectedCodexPackage.src.hash == codexPin.hash
      && lib.hasInfix codexPin.appName injectedCodexPackage.installPhase;
    expected = true;
  };

  testCodexAppDefaultPinPropagates = {
    expr =
      defaultCodexPackage.version == defaultCodexPin.version
      && defaultCodexPackage.src.url == defaultCodexPin.url
      && defaultCodexPackage.src.hash == defaultCodexPin.hash;
    expected = true;
  };

  testClaudeSettingsSchemaPinInjectable = {
    expr = hasInjectablePin ../lib/mk-claude-settings-validator.nix "schemaPin";
    expected = true;
  };

  testClaudeSettingsSchemaInjectedPinPropagates = {
    expr = injectedSchemaValidator.schema == schemaPin;
    expected = true;
  };

  testClaudeSettingsSchemaDefaultPinPropagates = {
    expr = defaultSchemaValidator.schema == defaultSchemaPin;
    expected = true;
  };
}
