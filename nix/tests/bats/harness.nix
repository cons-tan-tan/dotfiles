{
  lib,
  pkgs,
  repoRoot,
}:
{
  environment,
  initializeGit ? false,
  name,
  nativeBuildInputs,
  requiredEnvironment,
  sourceFiles,
  testFiles,
}:
let
  batsPath = relative: repoRoot + "/${relative}";
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
  ''
