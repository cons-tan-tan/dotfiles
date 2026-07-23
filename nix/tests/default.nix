{
  lib,
  pkgs,
  publicApps,
  username,
  reservedCheckNames ? [ ],
}:
let
  nixRoot = ../.;
  repoRoot = ../..;
  testSuffix = ".test.nix";

  # 評価だけで完結するテストは実装の隣に置き、ファイル名から checks の
  # 名前を生成する。
  testFiles = builtins.filter (path: lib.hasSuffix testSuffix (builtins.baseNameOf path)) (
    lib.filesystem.listFilesRecursive nixRoot
  );

  testStem = path: lib.removeSuffix testSuffix (builtins.baseNameOf path);
  checkName = path: "${testStem path}-tests";
  discoveredCheckNames = map checkName testFiles;
  checkNames = discoveredCheckNames ++ builtins.attrNames fixedChecks ++ reservedCheckNames;
  duplicateCheckNames = builtins.filter (
    name: builtins.length (builtins.filter (other: other == name) checkNames) > 1
  ) (lib.unique checkNames);

  testContext = {
    inherit lib pkgs username;
  };

  # *.test.nix は lib.runTests 互換の生テスト attrset、またはそれを返す
  # attrset 引数関数とする。必要と宣言した引数だけを共通 context から渡す。
  loadSuite =
    path:
    let
      imported = import path;
    in
    if builtins.isFunction imported then
      imported (builtins.intersectAttrs (builtins.functionArgs imported) testContext)
    else
      imported;

  validateSuite =
    path: suite:
    if !builtins.isAttrs suite then
      throw "${toString path} must return an attribute set"
    else
      let
        names = builtins.attrNames suite;
        invalidNames = builtins.filter (name: !lib.hasPrefix "test" name) names;
        invalidCases = builtins.filter (
          name:
          let
            testCase = suite.${name};
          in
          !(builtins.isAttrs testCase && testCase ? expr && testCase ? expected)
        ) names;
      in
      if names == [ ] then
        throw "${toString path} does not define any tests"
      else if invalidNames != [ ] then
        throw "${toString path} contains non-test attributes: ${builtins.toJSON invalidNames}"
      else if invalidCases != [ ] then
        throw "${toString path} contains invalid test cases: ${builtins.toJSON invalidCases}"
      else
        null;

  mkEvalCheck =
    path:
    let
      suite = loadSuite path;
      validation = validateSuite path suite;
      failures = lib.debug.runTests suite;
      result = lib.debug.throwTestFailures { inherit failures; };
      name = checkName path;
    in
    {
      inherit name;
      value = builtins.seq validation (builtins.seq result (pkgs.runCommand name { } ''touch "$out"''));
    };

  evalChecks = lib.listToAttrs (map mkEvalCheck testFiles);
  updatePinsCore = pkgs.callPackage ../apps/update-pins { };
  updatePinsSmoke = pkgs.callPackage ../apps/update-pins/smoke.nix { };
  applySecretsCore = pkgs.callPackage ../apps/apply-secrets { };
  applyNixSettingsCore = pkgs.callPackage ../apps/apply-nix-settings { };
  codexConfigHelper = pkgs.callPackage ../modules/home/programs/codex/helper { };
  safeFetch = pkgs.callPackage ../packages/safe-fetch { };
  curlFetch = pkgs.dotfilesPackages.curl-fetch;
  ghApiGet = pkgs.dotfilesPackages.gh-api-get;
  safeFetchCheck = pkgs.linkFarm "safe-fetch-rust" [
    {
      name = "core";
      path = safeFetch.core;
    }
    {
      name = "curl-fetch";
      path = curlFetch;
    }
    {
      name = "gh-api-get";
      path = ghApiGet;
    }
  ];

  claudeFixture = pkgs.writeShellApplication {
    name = "claude";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf 'path:%s\n' "$PATH" >"$TEST_TMPDIR/result"
      printf 'arg:%s\n' "$@" >>"$TEST_TMPDIR/result"
    '';
  };
  herdrPluginFixture = pkgs.runCommand "herdr-plugin-fixture" { } ''
    mkdir -p "$out"
    touch "$out/plugin.json"
  '';
  claudeWrapperTestPackage = pkgs.callPackage ../packages/claude-code/wrapped-package.nix {
    claudeCode = claudeFixture;
    herdrPlugin = herdrPluginFixture;
  };

  codexFixture = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf 'arg:%s\n' "$@" >"$TEST_TMPDIR/result"
    '';
  };
  herdrSkillFixture = pkgs.runCommand "herdr-skill-fixture" { } ''
    mkdir -p "$out"
    touch "$out/SKILL.md"
  '';
  codexWrapperTestPackage = pkgs.callPackage ../packages/codex/wrapped-package.nix {
    codex = codexFixture;
    herdrSkillPath = "${herdrSkillFixture}/SKILL.md";
  };

  piFixture = pkgs.writeShellApplication {
    name = "pi";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf 'package:%s\nskip:%s\ntelemetry:%s\n' \
        "$PI_PACKAGE_DIR" "$PI_SKIP_VERSION_CHECK" "$PI_TELEMETRY" >"$TEST_TMPDIR/result"
      printf 'arg:%s\n' "$@" >>"$TEST_TMPDIR/result"
    '';
  };
  piManagedPackageFixture = pkgs.runCommand "pi-managed-package-fixture" { } ''
    mkdir -p "$out"
  '';
  piWrapperTestPackage = pkgs.callPackage ../packages/pi/wrapped-package.nix {
    packageDir = piManagedPackageFixture;
    pi = piFixture;
  };

  herdrFixture = pkgs.writeShellApplication {
    name = "herdr";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$@" >"$TEST_TMPDIR/package-args"
    '';
  };
  herdrSleepFixture = pkgs.writeShellApplication {
    name = "herdr-sleep-fixture";
    text = "exit 0";
  };
  herdrWrapperTestPackage = pkgs.callPackage ../packages/herdr/wrapped-package.nix {
    herdr = herdrFixture;
    sleepBin = lib.getExe herdrSleepFixture;
  };

  drawioFixture = pkgs.writeShellApplication {
    name = "drawio";
    text = "exit 99";
  };
  drawioWrapperTestPackage = pkgs.callPackage ../packages/drawio-headless {
    drawio = drawioFixture;
  };

  wslRealpathFixture = pkgs.writeShellApplication {
    name = "realpath";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$#" "$@" >"$TEST_TMPDIR/package-realpath.args"
      printf '%s\n' "/package/resolved path"
    '';
  };
  wslpathFixture = pkgs.writeShellApplication {
    name = "wslpath";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$#" "$@" >"$TEST_TMPDIR/package-wslpath.args"
      printf '%s\n' 'Z:\package\resolved path'
    '';
  };
  wslHandlerFixture = pkgs.writeShellApplication {
    name = "rundll32.exe";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$#" "$@" >"$TEST_TMPDIR/package-handler.args"
    '';
  };
  wslOpenTestPackage = pkgs.callPackage ../modules/wsl/wsl-open-package.nix {
    realpathBin = lib.getExe wslRealpathFixture;
    rundll32Bin = lib.getExe wslHandlerFixture;
    wslpathBin = lib.getExe wslpathFixture;
  };

  ghqFetchAllSmokePackage =
    let
      fakeGhq = pkgs.writeShellApplication {
        name = "ghq";
        text = ''printf '%s\n' /tmp/repo'';
      };
      fakeGit = pkgs.writeShellApplication {
        name = "git";
        text = "exit 0";
      };
    in
    pkgs.callPackage ../packages/ghq-fetch-all {
      ghq = fakeGhq;
      git = fakeGit;
    };

  fixedChecks = {
    update-pins-rust = updatePinsCore;
    update-pins-smoke = updatePinsSmoke;
    apply-secrets-rust = applySecretsCore;
    apply-nix-settings-rust = applyNixSettingsCore;
    codex-config-helper-rust = codexConfigHelper;
    safe-fetch-rust = safeFetchCheck;

    workflow-lint-tests =
      pkgs.runCommand "workflow-lint-tests"
        {
          nativeBuildInputs = [
            pkgs.actionlint
            pkgs.shellcheck
          ];
        }
        ''
          actionlint ${repoRoot}/.github/workflows/*.yaml
          touch "$out"
        '';

    package-smoke-tests =
      pkgs.runCommand "package-smoke-tests"
        {
          nativeBuildInputs = [
            pkgs.dotfilesPackages.agent-browser
            pkgs.dotfilesPackages.agent-slack
            pkgs.dotfilesPackages.difit
          ];
        }
        ''
          agent_browser_version="$(agent-browser --version 2>&1)"
          test -n "$agent_browser_version"

          agent_slack_version="$(agent-slack --version 2>&1)"
          test -n "$agent_slack_version"

          test "$(difit --version)" = "${pkgs.dotfilesPackages.difit.version}"
          difit --help >/dev/null

          # The service starts the package directly, so every subprocess must
          # remain available without inheriting the activating user's PATH.
          PATH=/nonexistent ${ghqFetchAllSmokePackage}/bin/ghq-fetch-all

          touch "$out"
        '';

    bats-tests =
      pkgs.runCommand "bats-tests"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.bats
            pkgs.git
            pkgs.gnutar
            pkgs.gzip
            pkgs.jq
            pkgs.zip
            pkgs.yq-go
            applySecretsCore
            applyNixSettingsCore
            ghApiGet
            safeFetch.core
            curlFetch
            updatePinsCore
          ];
          APPLY_SECRETS_TEST_BIN = lib.getExe applySecretsCore;
          APPLY_NIX_SETTINGS_TEST_BIN = lib.getExe applyNixSettingsCore;
          APPLY_NIX_SETTINGS_PUBLIC_BIN = publicApps.apply-nix-settings.program;
          APPLY_SECRETS_PUBLIC_BIN = publicApps.apply-secrets.program;
          CURL_FETCH_PUBLIC_BIN = lib.getExe curlFetch;
          CURL_FETCH_TEST_BIN = "${safeFetch.core}/bin/curl-fetch";
          GH_API_GET_EXTENSION_ROOT = ghApiGet;
          GH_API_GET_PUBLIC_BIN = lib.getExe ghApiGet;
          GH_API_GET_TEST_BIN = "${safeFetch.core}/bin/gh-api-get";
          CLAUDE_WRAPPER_TEST_PACKAGE = claudeWrapperTestPackage;
          CODEX_WRAPPER_TEST_PACKAGE = codexWrapperTestPackage;
          DRAWIO_WRAPPER_TEST_PACKAGE =
            if pkgs.stdenv.hostPlatform.isLinux then drawioWrapperTestPackage else "";
          HERDR_WRAPPER_TEST_PACKAGE = herdrWrapperTestPackage;
          HOST_APP_KIND = if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "home-manager";
          HOST_BUILD_PUBLIC_BIN = publicApps.build.program;
          HOST_SWITCH_PUBLIC_BIN = publicApps.switch.program;
          PI_WRAPPER_TEST_PACKAGE = piWrapperTestPackage;
          UPDATE_PINS_TEST_BIN = lib.getExe updatePinsCore;
          WSL_OPEN_TEST_PACKAGE = wslOpenTestPackage;
        }
        ''
          cp -R ${repoRoot} repo
          chmod -R u+w repo
          cd repo
          git init -q
          bats --print-output-on-failure tests/
          touch "$out"
        '';
  };
in
# checks は右辺優先で結合されるため、呼び出し元の予約名も含めて検査し、
# suite や既存 gate が暗黙に上書きされる前に失敗させる。
if duplicateCheckNames != [ ] then
  throw "duplicate test check names: ${builtins.toJSON duplicateCheckNames}"
else
  evalChecks // fixedChecks
