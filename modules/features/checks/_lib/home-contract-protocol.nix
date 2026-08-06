{ lib }:
let
  duplicateNames =
    names:
    builtins.filter (name: builtins.length (builtins.filter (candidate: candidate == name) names) > 1) (
      lib.unique names
    );
in
{
  validateDiscovery =
    { contractNames }:
    let
      duplicates = duplicateNames contractNames;
    in
    if contractNames == [ ] then
      throw "No Feature-owned Home contracts were discovered"
    else if duplicates != [ ] then
      throw "Duplicate Feature-owned Home contract names: ${builtins.toJSON duplicates}"
    else
      null;

  loadContract =
    {
      context,
      contractName,
      declaration,
      mkContract,
      source,
    }:
    let
      functionArgs = if builtins.isFunction declaration then builtins.functionArgs declaration else { };
      missingRequiredArgs = builtins.filter (
        name: !functionArgs.${name} && !builtins.hasAttr name context
      ) (builtins.attrNames functionArgs);
      descriptor =
        if builtins.isFunction declaration then
          declaration (builtins.intersectAttrs functionArgs context)
        else
          declaration;
      descriptorNames = if builtins.isAttrs descriptor then builtins.attrNames descriptor else [ ];
    in
    if missingRequiredArgs != [ ] then
      throw "${source} requires unavailable Home contract arguments: ${builtins.toJSON missingRequiredArgs}"
    else if !builtins.isAttrs descriptor then
      throw "${source} must return a Home contract descriptor"
    else if
      descriptorNames != [
        "describe"
        "expected"
      ]
    then
      throw "${source} Home contract descriptor must contain exactly describe and expected"
    else if !builtins.isFunction descriptor.describe || !builtins.isFunction descriptor.expected then
      throw "${source} Home contract descriptor fields must be functions"
    else
      mkContract {
        inherit (descriptor) describe expected;
        name = "${contractName}-home-contract";
      };
}
