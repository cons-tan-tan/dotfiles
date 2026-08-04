# human-facing policyをcompilerのsemantic rule形式へ展開する。
{ lib }:
{
  guarded =
    profile:
    {
      guidance ? null,
      deny,
    }:
    {
      decision = true;
      optionSyntax = {
        valueTaking = [ ];
        optionalEquals = [ ];
      }
      // (profile.optionSyntax or { });
      deny = lib.mapAttrsToList (
        condition: details:
        details
        // {
          when.options.all =
            profile.conditions.${condition} or (throw "command profile has no condition named ${condition}");
        }
      ) deny;
    }
    // lib.optionalAttrs (guidance != null) { inherit guidance; };
}
