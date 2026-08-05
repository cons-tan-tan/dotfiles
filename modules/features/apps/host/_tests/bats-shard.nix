{
  group = "shellWrappers";
  testFiles = [
    "modules/features/apps/host/_tests/apply-winget.bats"
    "modules/features/apps/host/_tests/darwin-apps.bats"
    "modules/features/apps/host/_tests/linux-host-apps.bats"
  ];
  sourceFiles = [
    "modules/features/apps/host/_scripts/apply-winget.sh"
    "modules/features/apps/host/_scripts/darwin-build.sh"
    "modules/features/apps/host/_scripts/darwin-switch.sh"
    "modules/features/apps/host/_scripts/linux-host-build.sh"
    "modules/features/apps/host/_scripts/linux-host-switch.sh"
  ];
}
