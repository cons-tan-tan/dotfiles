# CLI所有のprofileが利用する共通abbreviation builderを確認する。
{ lib }:
let
  profile = import ../../_lib/command-policy/profile.nix { inherit lib; };
  ambiguous = profile.mkAbbreviatedLongOptionProfile {
    options = [
      "--force"
      "--format"
    ];
    valueTaking = [ "--force" ];
    conditions.force = [ { options = [ "--force" ]; } ];
  };
  canonicalPrefix = profile.mkAbbreviatedLongOptionProfile {
    options = [
      "--foo"
      "--foobar"
    ];
    valueTaking = [ "--foo" ];
    conditions.foo = [ { options = [ "--foo" ]; } ];
  };
in
{
  testAbbreviatedLongOptionProfileGeneratesOnlyUniqueAbbreviations = {
    expr = {
      forceValueAliases = ambiguous.optionSyntax.valueTaking;
      forceConditionAliases = builtins.head ambiguous.conditions.force;
    };
    expected = {
      forceValueAliases = [
        "--forc"
        "--force"
      ];
      forceConditionAliases = [
        "--forc"
        "--force"
      ];
    };
  };

  testAbbreviatedLongOptionProfilePreservesCanonicalPrefix = {
    expr = {
      valueAliases = canonicalPrefix.optionSyntax.valueTaking;
      conditionAliases = builtins.head canonicalPrefix.conditions.foo;
    };
    expected = {
      valueAliases = [ "--foo" ];
      conditionAliases = [ "--foo" ];
    };
  };
}
