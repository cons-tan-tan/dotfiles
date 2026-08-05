{
  rustCli,
  safeFetch,
  shellWrappers,
  standaloneShards,
}:
standaloneShards
++ [
  {
    name = "safe-fetch-e2e";
    fixture = "safeFetch";
    testFiles = safeFetch.testFiles;
    sourceFiles = safeFetch.sourceFiles ++ [
      "modules/features/checks/_interface/bats/test-helper.bash"
    ];
    initializeGit = false;
    platformPredicate = _platform: true;
  }
  {
    name = "rust-cli-e2e";
    fixture = "rustCli";
    testFiles = rustCli.testFiles;
    sourceFiles = rustCli.sourceFiles ++ [ "modules/features/checks/_interface/bats/test-helper.bash" ];
    initializeGit = false;
    platformPredicate = _platform: true;
  }
  {
    name = "shell-wrapper-tests";
    fixture = "shellWrappers";
    testFiles = shellWrappers.testFiles;
    sourceFiles = shellWrappers.sourceFiles ++ [
      "modules/features/checks/_interface/bats/test-helper.bash"
    ];
    initializeGit = true;
    platformPredicate = _platform: true;
  }
]
