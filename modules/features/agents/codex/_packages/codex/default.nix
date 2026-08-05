{
  callPackage,
  codex,
}:
{
  mkWrappedPackage =
    { herdrSkillPath }:
    callPackage ./wrapped-package.nix {
      inherit codex herdrSkillPath;
    };
}
