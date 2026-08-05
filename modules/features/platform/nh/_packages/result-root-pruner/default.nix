{
  coreutils,
  findutils,
  writeShellApplication,
}:
writeShellApplication {
  name = "nh-prune-result-roots";
  runtimeInputs = [
    coreutils
    findutils
  ];
  text = builtins.readFile ./nh-prune-result-roots.sh;
}
