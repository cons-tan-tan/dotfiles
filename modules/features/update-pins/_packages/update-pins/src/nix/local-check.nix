{
  getEnv,
  getFlake,
  repoRoot,
  system,
}:
let
  flake = getFlake (toString repoRoot);
  checks = builtins.getAttr system flake.checks;
in
builtins.getAttr (getEnv "UPDATE_PINS_CHECK") checks
