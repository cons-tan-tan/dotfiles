{
  libPath,
  manifestPath,
  policyPath,
  skillPolicyPath,
}:
let
  lib = import libPath;
  manifest = builtins.fromJSON (builtins.readFile manifestPath);
  inherit (import skillPolicyPath { inherit lib; }) prepareSkill;
  inherit (import policyPath { inherit lib; }) defaultInheritedFrontmatterFields;
  body = manifest.body or null;
  bodyTransform =
    if body == null then
      null
    else
      context:
      let
        transformer = import body.program;
      in
      assert lib.assertMsg (lib.isFunction transformer)
        "skill ${manifest.name} customization.body.program must evaluate to a function";
      transformer (
        context
        // {
          inherit lib;
          arguments = body.arguments or { };
        }
      );
  customization = manifest.customization // {
    body = bodyTransform;
  };
  prepared = prepareSkill {
    inherit (manifest) name root requireExplicitFieldDecisions;
    inherit customization;
    defaultInheritedFields = defaultInheritedFrontmatterFields;
  } (builtins.readFile (manifest.root + "/SKILL.md"));
in
{
  output = {
    "SKILL.md" = prepared.skillMd;
  };
}
