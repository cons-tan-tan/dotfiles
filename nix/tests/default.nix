{
  advisoryDb,
  advisoryDbLastModified,
  homeManager,
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
    inherit
      homeManager
      lib
      pkgs
      username
      ;
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
  agentConfigHelper = pkgs.callPackage ../libexec/agent-config-helper { };
  awsConfigHelper = pkgs.callPackage ../packages/aws/config-helper { };
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

  mkRustClippyCheck =
    {
      name,
      package,
      flags,
    }:
    pkgs.rustPlatform.buildRustPackage {
      pname = "${name}-clippy";
      inherit (package) version src cargoDeps;

      nativeBuildInputs = [ pkgs.clippy ];
      auditable = false;
      doCheck = false;

      buildPhase = ''
        runHook preBuild
        cargo clippy --offline --locked ${lib.escapeShellArgs flags} -- -D warnings
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        touch "$out"
        runHook postInstall
      '';
    };

  rustClippyChecks = {
    apply-secrets = mkRustClippyCheck {
      name = "apply-secrets";
      package = applySecretsCore;
      flags = [
        "--all-targets"
        "--all-features"
      ];
    };
    apply-nix-settings = mkRustClippyCheck {
      name = "apply-nix-settings";
      package = applyNixSettingsCore;
      flags = [
        "--all-targets"
        "--all-features"
      ];
    };
    safe-fetch = mkRustClippyCheck {
      name = "safe-fetch";
      package = safeFetch.core;
      flags = [
        "--all-targets"
        "--all-features"
      ];
    };
    agent-config-helper = mkRustClippyCheck {
      name = "agent-config-helper";
      package = agentConfigHelper;
      flags = [
        "--all-targets"
        "--all-features"
      ];
    };
    aws-config-helper = mkRustClippyCheck {
      name = "aws-config-helper";
      package = awsConfigHelper;
      flags = [
        "--all-targets"
        "--all-features"
      ];
    };
    update-pins = mkRustClippyCheck {
      name = "update-pins";
      package = updatePinsCore;
      flags = [
        "--all-targets"
        "--features"
        "smoke"
      ];
    };
    update-pins-smoke = mkRustClippyCheck {
      name = "update-pins-smoke";
      package = updatePinsSmoke;
      flags = [
        "--all-targets"
        "--no-default-features"
        "--features"
        "smoke"
      ];
    };
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
    sleepctl = mkRustClippyCheck {
      name = "sleepctl";
      package = pkgs.callPackage ../packages/sleepctl { };
      flags = [ "--all-targets" ];
    };
  };

  rustClippy = pkgs.linkFarm "rust-clippy" (
    lib.mapAttrsToList (name: path: { inherit name path; }) rustClippyChecks
  );

  rustLockfiles = [
    {
      owner = "update-pins";
      path = ../apps/update-pins/Cargo.lock;
      ignoredAdvisories = [ ];
    }
    {
      owner = "apply-secrets";
      path = ../apps/apply-secrets/Cargo.lock;
      ignoredAdvisories = [ ];
    }
    {
      owner = "apply-nix-settings";
      path = ../apps/apply-nix-settings/Cargo.lock;
      ignoredAdvisories = [ ];
    }
    {
      owner = "safe-fetch";
      path = ../packages/safe-fetch/Cargo.lock;
      ignoredAdvisories = [ ];
    }
    {
      owner = "agent-config-helper";
      path = ../libexec/agent-config-helper/Cargo.lock;
      ignoredAdvisories = [ ];
    }
    {
      owner = "aws-config-helper";
      path = ../packages/aws/config-helper/Cargo.lock;
      ignoredAdvisories = [ ];
    }
    {
      owner = "shellfirm";
      path = ../packages/shellfirm/Cargo.lock;
      ignoredAdvisories = [
        {
          id = "RUSTSEC-2026-0002";
          reviewedAt = "2026-07-24";
          # 2026-11-01T00:00:00Z. ratatui 0.29 is the only lru consumer and
          # does not call the affected LruCache::iter_mut API. Remove this
          # exception when shellfirm upgrades to ratatui with lru >= 0.16.3.
          expiresAt = 1793491200;
        }
      ];
    }
    {
      owner = "sleepctl";
      path = ../packages/sleepctl/Cargo.lock;
      ignoredAdvisories = [ ];
    }
  ];

  discoveredRustLockfiles = builtins.filter (path: builtins.baseNameOf path == "Cargo.lock") (
    lib.filesystem.listFilesRecursive nixRoot
  );
  declaredRustLockfiles = map (lock: lock.path) rustLockfiles;
  rustLockfileInventoryValidation =
    if
      lib.sort lib.lessThan (map toString discoveredRustLockfiles)
      == lib.sort lib.lessThan (map toString declaredRustLockfiles)
    then
      null
    else
      throw "rust advisory lockfile inventory is incomplete";

  ignoredRustAdvisories = lib.concatMap (
    lock: map (advisory: advisory // { inherit (lock) owner; }) lock.ignoredAdvisories
  ) rustLockfiles;
  rustAdvisoryLabel = advisory: "${advisory.owner}:${advisory.id} (reviewed ${advisory.reviewedAt})";
  expiredRustAdvisoriesAt =
    timestamp:
    map rustAdvisoryLabel (
      builtins.filter (advisory: timestamp >= advisory.expiresAt) ignoredRustAdvisories
    );
  rustAdvisoryExpiryContractValidation =
    if
      builtins.all (
        advisory:
        !(builtins.elem (rustAdvisoryLabel advisory) (expiredRustAdvisoriesAt (advisory.expiresAt - 1)))
        && builtins.elem (rustAdvisoryLabel advisory) (expiredRustAdvisoriesAt advisory.expiresAt)
      ) ignoredRustAdvisories
    then
      null
    else
      throw "rust advisory expiry boundary validation failed";
  rustAdvisoryExpiryValidation =
    let
      expired = expiredRustAdvisoriesAt advisoryDbLastModified;
    in
    if expired == [ ] then
      null
    else
      throw "rust advisory exceptions expired for pinned DB: ${builtins.toJSON expired}";

  rustAdvisories = builtins.seq rustLockfileInventoryValidation (
    builtins.seq rustAdvisoryExpiryContractValidation (
      builtins.seq rustAdvisoryExpiryValidation (
        pkgs.runCommand "rust-advisories"
          {
            nativeBuildInputs = [ pkgs.cargo-audit ];
          }
          ''
            export CARGO_HOME="$TMPDIR/cargo-home"
            export CARGO_NET_OFFLINE=true
            mkdir -p "$CARGO_HOME"

            ${lib.concatMapStringsSep "\n" (
              lock:
              # Yanked status requires a crates.io registry index, which is not
              # pinned here, so this reproducible gate excludes it. RustSec
              # vulnerabilities and unsound warnings fail. Unmaintained warnings
              # remain visible without being denied.
              ''
                echo "Auditing ${lock.owner}: ${lock.path}"
                cargo-audit audit \
                  --color never \
                  --db ${advisoryDb} \
                  --deny unsound \
                  --no-fetch \
                  --no-yanked \
                  ${
                    lib.concatMapStringsSep " " (
                      advisory: "--ignore ${lib.escapeShellArg advisory.id}"
                    ) lock.ignoredAdvisories
                  } \
                  --file ${lock.path}
              '') rustLockfiles}

            touch "$out"
          ''
      )
    )
  );

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

  awsLoginFixture = pkgs.writeShellApplication {
    name = "aws";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$@" >"$TEST_TMPDIR/aws-args"
      if [[ "''${AWS_LOGIN_TEST_MODE:-success}" == fail ]]; then
        exit 7
      fi
      : "''${AWS_CONFIG_FILE:?}"
      printf '%s\n' 'login_session = fixture-session' >>"$AWS_CONFIG_FILE"
    '';
  };
  awsLoginTestBaseline = pkgs.writeText "aws-login-test-baseline" ''
    [profile test]
    output = json
  '';
  awsLoginTestPackage = pkgs.callPackage ../packages/aws/login-package.nix {
    awscli2 = awsLoginFixture;
    configHelper = awsConfigHelper;
    loginConfigFile = awsLoginTestBaseline;
  };
  awsConfigReconcileTestBaseline = pkgs.writeText "aws-config-reconcile-test-baseline" ''
    [profile test]
    region = baseline
    credential_process = command
  '';
  awsConfigReconcileTestPackage = pkgs.callPackage ../packages/aws/reconcile-package.nix {
    baselineFile = awsConfigReconcileTestBaseline;
    configHelper = awsConfigHelper;
    managedSections = [ "profile test" ];
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

  batsShardSpecs = [
    {
      name = "update-pins-e2e";
      testFiles = [ "tests/update-pins.bats" ];
      sourceFiles = [
        "flake.lock"
        "flake.nix"
        "nix/packages/shellfirm/Cargo.lock"
        "nix/pins"
      ];
      nativeBuildInputs = [
        pkgs.git
        pkgs.gnutar
        pkgs.gzip
        pkgs.jq
        pkgs.zip
        updatePinsCore
      ];
      environment = {
        UPDATE_PINS_TEST_BIN = lib.getExe updatePinsCore;
      };
      requiredEnvironment = [ "UPDATE_PINS_TEST_BIN" ];
      initializeGit = true;
      platformPredicate = _platform: true;
    }
    {
      name = "safe-fetch-e2e";
      testFiles = [
        "tests/curl-fetch.bats"
        "tests/gh-api-get.bats"
      ];
      sourceFiles = [ ];
      nativeBuildInputs = [
        ghApiGet
        safeFetch.core
        curlFetch
      ];
      environment = {
        CURL_FETCH_PUBLIC_BIN = lib.getExe curlFetch;
        CURL_FETCH_TEST_BIN = "${safeFetch.core}/bin/curl-fetch";
        GH_API_GET_EXTENSION_ROOT = ghApiGet;
        GH_API_GET_PUBLIC_BIN = lib.getExe ghApiGet;
        GH_API_GET_TEST_BIN = "${safeFetch.core}/bin/gh-api-get";
      };
      requiredEnvironment = [
        "CURL_FETCH_PUBLIC_BIN"
        "CURL_FETCH_TEST_BIN"
        "GH_API_GET_EXTENSION_ROOT"
        "GH_API_GET_PUBLIC_BIN"
        "GH_API_GET_TEST_BIN"
      ];
      platformPredicate = _platform: true;
    }
    {
      name = "rust-cli-e2e";
      testFiles = [
        "tests/apply-nix-settings.bats"
        "tests/apply-secrets.bats"
      ];
      sourceFiles = [ ];
      nativeBuildInputs = [
        applyNixSettingsCore
        applySecretsCore
      ];
      environment = {
        APPLY_NIX_SETTINGS_PUBLIC_BIN = publicApps.apply-nix-settings.program;
        APPLY_NIX_SETTINGS_TEST_BIN = lib.getExe applyNixSettingsCore;
        APPLY_SECRETS_PUBLIC_BIN = publicApps.apply-secrets.program;
        APPLY_SECRETS_TEST_BIN = lib.getExe applySecretsCore;
      };
      requiredEnvironment = [
        "APPLY_NIX_SETTINGS_PUBLIC_BIN"
        "APPLY_NIX_SETTINGS_TEST_BIN"
        "APPLY_SECRETS_PUBLIC_BIN"
        "APPLY_SECRETS_TEST_BIN"
      ];
      platformPredicate = _platform: true;
    }
    {
      name = "shell-wrapper-tests";
      testFiles = [
        "tests/apply-winget.bats"
        "tests/aws-config-activation.bats"
        "tests/aws-login.bats"
        "tests/claude-wrapper.bats"
        "tests/codex-wrapper.bats"
        "tests/darwin-apps.bats"
        "tests/drawio-headless.bats"
        "tests/ghq-fetch-all.bats"
        "tests/herdr-wrapper.bats"
        "tests/home-manager-apps.bats"
        "tests/nh-result-root-pruner.bats"
        "tests/pi-package-manager.bats"
        "tests/pi-wrapper.bats"
        "tests/wsl-open.bats"
        "tests/wsl-set-ssh-auth-sock.bats"
      ];
      sourceFiles = [
        "nix/apps/apply-winget.sh"
        "nix/apps/darwin-build.sh"
        "nix/apps/darwin-switch.sh"
        "nix/apps/home-manager-build.sh"
        "nix/apps/home-manager-switch.sh"
        "nix/modules/wsl/wsl-open.sh"
        "nix/packages/aws/aws-login.sh"
        "nix/packages/aws/reconcile-package.nix"
        "nix/packages/claude-code/claude-wrapper.sh"
        "nix/packages/codex/codex-wrapper.sh"
        "nix/packages/drawio-headless/drawio-wrapper.sh"
        "nix/packages/ghq-fetch-all/ghq-fetch-all.sh"
        "nix/packages/herdr/herdr-wrapper.sh"
        "nix/packages/nh-result-root-pruner/nh-prune-result-roots.sh"
        "nix/packages/pi/package-manager.sh"
        "nix/packages/pi/pi-wrapper.sh"
        "nix/packages/wsl-set-ssh-auth-sock/set-ssh-auth-sock.sh"
        "tests/test-helper.bash"
      ];
      nativeBuildInputs = [
        pkgs.git
        awsConfigReconcileTestPackage
        awsLoginTestPackage
        claudeWrapperTestPackage
        codexWrapperTestPackage
        herdrWrapperTestPackage
        piWrapperTestPackage
        wslOpenTestPackage
      ]
      ++ lib.optional pkgs.stdenv.hostPlatform.isLinux drawioWrapperTestPackage;
      environment = {
        AWS_CONFIG_RECONCILE_TEST_PACKAGE = awsConfigReconcileTestPackage;
        AWS_LOGIN_TEST_PACKAGE = awsLoginTestPackage;
        CLAUDE_WRAPPER_TEST_PACKAGE = claudeWrapperTestPackage;
        CODEX_WRAPPER_TEST_PACKAGE = codexWrapperTestPackage;
        DRAWIO_WRAPPER_TEST_PACKAGE =
          if pkgs.stdenv.hostPlatform.isLinux then drawioWrapperTestPackage else "";
        HERDR_WRAPPER_TEST_PACKAGE = herdrWrapperTestPackage;
        HOST_APP_KIND = if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "home-manager";
        HOST_BUILD_PUBLIC_BIN = publicApps.build.program;
        HOST_SWITCH_PUBLIC_BIN = publicApps.switch.program;
        PI_WRAPPER_TEST_PACKAGE = piWrapperTestPackage;
        WSL_OPEN_TEST_PACKAGE = wslOpenTestPackage;
      };
      requiredEnvironment = [
        "AWS_CONFIG_RECONCILE_TEST_PACKAGE"
        "AWS_LOGIN_TEST_PACKAGE"
        "CLAUDE_WRAPPER_TEST_PACKAGE"
        "CODEX_WRAPPER_TEST_PACKAGE"
        "HERDR_WRAPPER_TEST_PACKAGE"
        "HOST_APP_KIND"
        "HOST_BUILD_PUBLIC_BIN"
        "HOST_SWITCH_PUBLIC_BIN"
        "PI_WRAPPER_TEST_PACKAGE"
        "WSL_OPEN_TEST_PACKAGE"
      ]
      ++ lib.optional pkgs.stdenv.hostPlatform.isLinux "DRAWIO_WRAPPER_TEST_PACKAGE";
      initializeGit = true;
      platformPredicate = _platform: true;
    }
    {
      name = "workflow-policy-tests";
      testFiles = [ "tests/update-pins-smoke-workflow.bats" ];
      sourceFiles = [
        ".github/workflows/ci.yaml"
        ".github/workflows/update-pins-smoke.yaml"
      ];
      nativeBuildInputs = [ pkgs.yq-go ];
      environment = { };
      requiredEnvironment = [ ];
      platformPredicate = _platform: true;
    }
  ];

  batsPath = relative: repoRoot + "/${relative}";
  discoveredBatsFiles = lib.sort builtins.lessThan (
    map (path: lib.removePrefix "${toString repoRoot}/" (toString path)) (
      builtins.filter (path: lib.hasSuffix ".bats" (toString path)) (
        lib.filesystem.listFilesRecursive (repoRoot + "/tests")
      )
    )
  );
  declaredBatsFiles = lib.concatMap (shard: shard.testFiles) batsShardSpecs;
  duplicateBatsFiles = builtins.filter (
    file: builtins.length (builtins.filter (other: other == file) declaredBatsFiles) > 1
  ) (lib.unique declaredBatsFiles);
  missingBatsFiles = lib.subtractLists discoveredBatsFiles declaredBatsFiles;
  unknownBatsFiles = lib.subtractLists declaredBatsFiles discoveredBatsFiles;
  batsInventoryValidation =
    if duplicateBatsFiles != [ ] then
      throw "Bats files assigned to multiple shards: ${builtins.toJSON duplicateBatsFiles}"
    else if missingBatsFiles != [ ] then
      throw "Bats files missing from shard manifest: ${builtins.toJSON missingBatsFiles}"
    else if unknownBatsFiles != [ ] then
      throw "Bats shard manifest references missing files: ${builtins.toJSON unknownBatsFiles}"
    else
      true;

  mkBatsCheck =
    {
      name,
      testFiles,
      sourceFiles,
      nativeBuildInputs,
      environment,
      requiredEnvironment,
      platformPredicate,
      initializeGit ? false,
    }:
    assert platformPredicate pkgs.stdenv.hostPlatform;
    let
      shardSource = lib.fileset.toSource {
        root = repoRoot;
        fileset = lib.fileset.unions (map batsPath (testFiles ++ sourceFiles));
      };
      requiredFiles = testFiles ++ sourceFiles;
    in
    pkgs.runCommand name
      (
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.bats
          ]
          ++ nativeBuildInputs;
          passthru = {
            inherit testFiles;
          };
        }
        // environment
      )
      ''
        cp -R ${shardSource} repo
        chmod -R u+w repo
        cd repo

        for required in ${lib.escapeShellArgs requiredFiles}; do
          if [[ ! -e "$required" ]]; then
            echo "${name}: required shard source is missing: $required" >&2
            exit 1
          fi
        done

        ${lib.optionalString (requiredEnvironment != [ ]) ''
          for variable in ${lib.escapeShellArgs requiredEnvironment}; do
            if [[ -z "$(printenv "$variable")" ]]; then
              echo "${name}: required test environment is missing: $variable" >&2
              exit 1
            fi
          done
        ''}

        ${lib.optionalString initializeGit "git init -q"}
        bats --print-output-on-failure ${lib.escapeShellArgs testFiles}
        touch "$out"
      '';

  applicableBatsShardSpecs = builtins.filter (
    shard: shard.platformPredicate pkgs.stdenv.hostPlatform
  ) batsShardSpecs;
  batsChecks = lib.listToAttrs (
    map (
      shard:
      lib.nameValuePair shard.name (
        mkBatsCheck (
          builtins.removeAttrs shard [ "platformPredicate" ]
          // {
            inherit (shard) platformPredicate;
          }
        )
      )
    ) applicableBatsShardSpecs
  );
  batsShardNames = map (shard: shard.name) applicableBatsShardSpecs;

  fixedChecks = {
    update-pins-rust = updatePinsCore;
    update-pins-smoke = updatePinsSmoke;
    apply-secrets-rust = applySecretsCore;
    apply-nix-settings-rust = applyNixSettingsCore;
    agent-config-helper-rust = agentConfigHelper;
    aws-config-helper-rust = awsConfigHelper;
    safe-fetch-rust = safeFetchCheck;
    rust-clippy = rustClippy;
    rust-advisories = rustAdvisories;

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

    bats-tests = pkgs.linkFarm "bats-tests" (
      map (name: {
        inherit name;
        path = batsChecks.${name};
      }) batsShardNames
    );
  }
  // batsChecks;
in
# checks は右辺優先で結合されるため、呼び出し元の予約名も含めて検査し、
# suite や既存 gate が暗黙に上書きされる前に失敗させる。
if duplicateCheckNames != [ ] then
  throw "duplicate test check names: ${builtins.toJSON duplicateCheckNames}"
else
  builtins.seq batsInventoryValidation (evalChecks // fixedChecks)
