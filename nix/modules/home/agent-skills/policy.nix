{ lib }:
{
  # Descriptive metadata is safe to inherit globally. Fields that alter tools,
  # hooks, models, or invocation require an explicit per-skill opt-in.
  defaultInheritedFrontmatterFields = [
    "name"
    "description"
    "license"
    "compatibility"
    "metadata"
  ];

  mergeSkillDefinitions =
    externalSkills: localSkills:
    let
      duplicateSkillNames = lib.intersectLists (builtins.attrNames externalSkills) (
        builtins.attrNames localSkills
      );
    in
    assert lib.assertMsg (duplicateSkillNames == [ ])
      "agent skills cannot be both external and local: ${lib.concatStringsSep ", " duplicateSkillNames}";
    externalSkills // localSkills;
}
