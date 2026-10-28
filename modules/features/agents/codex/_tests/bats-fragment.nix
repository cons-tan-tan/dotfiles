{ pkgs }:
let
  agentPackageSources = import ../../base/_interface/package-sources.nix;
  codexFixture = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf 'arg:%s\n' "$@" >"$TEST_TMPDIR/result"
    '';
  };
  testPackage = pkgs.callPackage ../_packages/codex/wrapped-package.nix {
    codex = codexFixture;
  };
  profiledPackage = testPackage.override {
    commitProfiles = import ../../skills/_tests/commit-profiles-fixture.nix { inherit pkgs; };
  };
  hooksConfig = pkgs.callPackage ../_packages/hooks-config.nix {
    agentConfigHelper = pkgs.callPackage agentPackageSources.configHelper { };
    codex = pkgs.writeShellApplication {
      name = "codex";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.jq
      ];
      text = builtins.readFile ./hooks-app-server.sh;
    };
    hooksJsonPath = "/fixture/.codex/hooks.json";
    hooksJson = pkgs.writeText "test-codex-hooks.json" (
      builtins.toJSON {
        hooks.SessionStart = [
          {
            hooks = [
              {
                type = "command";
                command = "fixture-command";
                timeout = 10;
              }
            ];
          }
        ];
      }
    );
    managedHookManifest = pkgs.writeText "test-codex-hook-manifest.json" (
      builtins.toJSON [
        {
          eventName = "sessionStart";
          handlerType = "command";
          matcher = null;
          command = "fixture-command";
          timeoutSec = 10;
        }
      ]
    );
    baseMergePayloadJson = pkgs.writeText "test-codex-config-merge.json" ''
      {"model": "managed"}
    '';
    codexSchema = pkgs.writeText "test-codex-config-schema.json" (
      builtins.toJSON {
        type = "object";
        properties.preserved.type = "string";
      }
    );
  };
in
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.jq
      pkgs.libplist
      pkgs.ripgrep
      pkgs.unzip
      pkgs.xmlstarlet
      pkgs.zip
      testPackage
    ];
    environment = {
      CODEX_UPDATE_TEST_FIXTURE = "1";
      CODEX_WRAPPER_TEST_PACKAGE = testPackage;
      CODEX_PROFILED_TEST_PACKAGE = profiledPackage;
      CODEX_CONFIG_RECONCILE_TEST_PACKAGE = hooksConfig.reconcile;
      CODEX_HOOK_STATE_TEST_GENERATOR = hooksConfig.generateState;
      CODEX_HOOK_STATE_TEST_PAYLOAD = hooksConfig.mergePayload;
    };
    requiredEnvironment = [
      "CODEX_UPDATE_TEST_FIXTURE"
      "CODEX_WRAPPER_TEST_PACKAGE"
      "CODEX_PROFILED_TEST_PACKAGE"
      "CODEX_CONFIG_RECONCILE_TEST_PACKAGE"
      "CODEX_HOOK_STATE_TEST_GENERATOR"
      "CODEX_HOOK_STATE_TEST_PAYLOAD"
    ];
  };
  shard = {
    testFiles = [
      "modules/features/agents/codex/_tests/codex-wrapper.bats"
      "modules/features/agents/codex/_tests/update-app.bats"
      "modules/features/agents/codex/_tests/hooks-config.bats"
    ];
    sourceFiles = [
      "modules/features/agents/codex/_packages/codex/codex-wrapper.sh"
      "modules/features/agents/codex/_scripts/update-app.sh"
    ];
  };
}
