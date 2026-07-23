# pin ? fromJSON (readFile ...) の注入可能 default が誤って外れた時に検知する。
# 既存の herdr-package.test.nix は引数の存在だけを検査するため、default の
# 有無はここで全消費者と同じ契約として固定する。
{ lib }:
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

  testDifitPinInjectable = {
    expr = hasInjectablePin ./difit/default.nix "difitPin";
    expected = true;
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
