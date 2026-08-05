{ lib, pkgs }:
let
  testRoot = "/build/windows-companion-test/Users";
  mvFixture = pkgs.writeShellApplication {
    name = "windows-companion-deploy-mv-fixture";
    text = ''
      : "''${WINDOWS_COMPANION_DEPLOY_MV_STATE:?}"
      count=0
      if [[ -e $WINDOWS_COMPANION_DEPLOY_MV_STATE ]]; then
        read -r count <"$WINDOWS_COMPANION_DEPLOY_MV_STATE"
      fi
      count=$((count + 1))
      printf '%s\n' "$count" >"$WINDOWS_COMPANION_DEPLOY_MV_STATE"

      if [[ ''${WINDOWS_COMPANION_DEPLOY_MV_FAIL_AT:-} == "$count" ]]; then
        exit 71
      fi
      if [[ ''${WINDOWS_COMPANION_DEPLOY_MV_SIGNAL_BEFORE_AT:-} == "$count" ]]; then
        kill -TERM "$PPID"
        exit 143
      fi

      ${pkgs.coreutils}/bin/mv "$@"

      if [[ ''${WINDOWS_COMPANION_DEPLOY_MV_SIGNAL_AFTER_AT:-} == "$count" ]]; then
        kill -TERM "$PPID"
        exit 143
      fi
    '';
  };
  rsyncFixture = pkgs.writeShellApplication {
    name = "windows-companion-deploy-rsync-fixture";
    text = ''
      : "''${WINDOWS_COMPANION_DEPLOY_RSYNC_STATE:?}"
      count=0
      if [[ -e $WINDOWS_COMPANION_DEPLOY_RSYNC_STATE ]]; then
        read -r count <"$WINDOWS_COMPANION_DEPLOY_RSYNC_STATE"
      fi
      count=$((count + 1))
      printf '%s\n' "$count" >"$WINDOWS_COMPANION_DEPLOY_RSYNC_STATE"

      if [[ ''${WINDOWS_COMPANION_DEPLOY_RSYNC_FAIL_AT:-} == "$count" ]]; then
        exit 72
      fi

      ${pkgs.rsync}/bin/rsync "$@"

      if [[ ''${WINDOWS_COMPANION_DEPLOY_RSYNC_SIGNAL_AFTER_AT:-} == "$count" ]]; then
        kill -TERM "$PPID"
        exit 143
      fi
    '';
  };
  testPackage = pkgs.callPackage ../_packages/companion-deploy {
    mvBin = lib.getExe mvFixture;
    rootPrefix = testRoot;
    rsyncBin = lib.getExe rsyncFixture;
  };
in
{
  fixture = {
    nativeBuildInputs = [ pkgs.jq ];
    environment = {
      WINDOWS_COMPANION_DEPLOY_TEST_BIN = lib.getExe testPackage;
      WINDOWS_COMPANION_DEPLOY_TEST_ROOT = testRoot;
    };
    requiredEnvironment = [
      "WINDOWS_COMPANION_DEPLOY_TEST_BIN"
      "WINDOWS_COMPANION_DEPLOY_TEST_ROOT"
    ];
  };
  shard = {
    testFiles = [ "modules/features/windows/_tests/windows-companion-deploy.bats" ];
    sourceFiles = [ "modules/features/windows/_packages/companion-deploy/deploy.sh" ];
  };
}
