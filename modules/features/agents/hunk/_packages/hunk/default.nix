{
  hunkInput,
  stdenv,
}:
{
  package = hunkInput.packages.${stdenv.hostPlatform.system}.default;
}
