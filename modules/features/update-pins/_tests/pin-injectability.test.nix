# pin ? fromJSON (readFile ...) の注入可能 default が誤って外れた時に検知する。
# 既存の herdr-package.test.nix は引数の存在だけを検査するため、default の
# 有無はここで全消費者と同じ契約として固定する。
{ lib, pkgs }:
let
  hasInjectablePin = fn: argName: (builtins.functionArgs (import fn)).${argName} or false;
  updatePins = import ../_interface;
  agentPackageSources = import ../../agents/_interface/package-sources.nix;
  watchexec = import ../../development/watchexec/_interface;

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
    import agentPackageSources.codexApp (
      {
        inherit lib;
        stdenvNoCC.mkDerivation = attrs: attrs;
        fetchurl = attrs: attrs;
        unzip = "unzip";
      }
      // args
    );

  injectedCodexPackage = mkCodexPackage { pin = codexPin; };
  defaultCodexPin = lib.importJSON (agentPackageSources.codexApp + "/pin.json");
  defaultCodexPackage = mkCodexPackage { };

  shellfirmPin = {
    version = "99.88.77";
    srcHash = "sha256-shellfirm-marker";
  };

  mkShellfirmPackage =
    args:
    import agentPackageSources.shellfirm (
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
  defaultShellfirmPin = lib.importJSON (agentPackageSources.shellfirm + "/pin.json");
  defaultShellfirmPackage = mkShellfirmPackage { };

  difitPin = {
    srcHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    pnpmDepsHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
  };
  injectedDifitPackage = pkgs.dotfilesPackages.difit.override { difitPin = difitPin; };
  defaultDifitPin = lib.importJSON (agentPackageSources.difit + "/pin.json");
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
    updatePins.mkCandidatePackage {
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

  claudeSettingsValidatorSource = ../../agents/claude/_interface/settings-validator.nix;
  claudeSettingsSchema = ../../agents/claude/_interface/settings-schema.nix;

  mkSchemaValidator =
    args:
    import claudeSettingsValidatorSource (
      {
        pkgs.fetchurl = attrs: attrs;
        schemaPin = import claudeSettingsSchema;
      }
      // args
    );

  injectedSchemaValidator = mkSchemaValidator { inherit schemaPin; };
  defaultSchemaPin = import claudeSettingsSchema;
  defaultSchemaValidator = mkSchemaValidator { };
in
{
  testAgentBrowserPinInjectable = {
    expr = hasInjectablePin (agentPackageSources.browser + "/default.nix") "pin";
    expected = true;
  };

  testAgentSlackPinInjectable = {
    expr = hasInjectablePin (agentPackageSources.slack + "/default.nix") "pin";
    expected = true;
  };

  testHcomFamilyPinInjectable = {
    expr = hasInjectablePin (agentPackageSources.hcom + "/default.nix") "hcomPin";
    expected = true;
  };

  testHcomPackagePinInjectable = {
    expr = hasInjectablePin (agentPackageSources.hcom + "/package.nix") "hcomPin";
    expected = true;
  };

  testHerdrFamilyPinInjectable = {
    expr = hasInjectablePin (agentPackageSources.herdr + "/default.nix") "herdrPin";
    expected = true;
  };

  testHerdrPackagePinInjectable = {
    expr = hasInjectablePin (agentPackageSources.herdr + "/package.nix") "herdrPin";
    expected = true;
  };

  testShellfirmPinInjectable = {
    expr = hasInjectablePin (agentPackageSources.shellfirm + "/default.nix") "pin";
    expected = true;
  };

  testShellfirmInjectedPinPropagates = {
    expr =
      injectedShellfirmPackage.version == shellfirmPin.version
      && injectedShellfirmPackage.src.rev == "v${shellfirmPin.version}"
      && injectedShellfirmPackage.src.hash == shellfirmPin.srcHash
      && injectedShellfirmPackage.cargoLock.lockFile == agentPackageSources.shellfirm + "/Cargo.lock";
    expected = true;
  };

  testShellfirmDefaultPinPropagates = {
    expr =
      defaultShellfirmPackage.version == defaultShellfirmPin.version
      && defaultShellfirmPackage.src.rev == "v${defaultShellfirmPin.version}"
      && defaultShellfirmPackage.src.hash == defaultShellfirmPin.srcHash
      && defaultShellfirmPackage.cargoLock.lockFile == agentPackageSources.shellfirm + "/Cargo.lock";
    expected = true;
  };

  testDifitPinInjectable = {
    expr = hasInjectablePin (agentPackageSources.difit + "/default.nix") "difitPin";
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

  testWatchexecPinInjectable = {
    expr = hasInjectablePin watchexec.overlaySource "pin";
    expected = true;
  };

  testCodexAppPinInjectable = {
    expr = hasInjectablePin (agentPackageSources.codexApp + "/default.nix") "pin";
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
    expr = hasInjectablePin claudeSettingsValidatorSource "schemaPin";
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
