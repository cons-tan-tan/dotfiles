{
  bash,
  coreutils,
  findutils,
  ghq,
  git,
  writeShellApplication,
}:
writeShellApplication {
  name = "ghq-fetch-all";
  bashOptions = [
    "nounset"
    "pipefail"
  ];
  runtimeInputs = [
    bash
    ghq
    git
    coreutils
    findutils
  ];
  # The child shell receives the repository path as $1 from xargs.
  excludeShellChecks = [ "SC2016" ];
  text = builtins.readFile ./ghq-fetch-all.sh;
}
