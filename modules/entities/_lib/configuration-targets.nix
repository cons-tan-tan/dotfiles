{ lib }:
{
  den,
  system,
}:
let
  resolveTarget =
    {
      entities,
      environment,
      label,
      output,
    }:
    let
      candidates = lib.filterAttrs (
        _: entity: (entity.dotfiles.environment or null) == environment
      ) entities;
      candidateNames = builtins.attrNames candidates;
      candidateCount = builtins.length candidateNames;
      entityName = if candidateCount == 1 then builtins.head candidateNames else null;
      entity = if entityName == null then null else candidates.${entityName};
      intoAttr = if entity == null then null else entity.intoAttr or null;
      validIntoAttr =
        builtins.isList intoAttr
        && builtins.length intoAttr == 2
        && builtins.elemAt intoAttr 0 == output
        && builtins.isString (builtins.elemAt intoAttr 1)
        && builtins.elemAt intoAttr 1 != "";
    in
    if candidateCount != 1 then
      throw "${label} requires exactly one ${environment} entity for ${system}, found ${toString candidateCount}"
    else if !validIntoAttr then
      throw "${label} entity ${entityName} must declare intoAttr = [ \"${output}\" <non-empty-name> ]"
    else
      {
        inherit entityName;
        outputName = builtins.elemAt intoAttr 1;
      };

  hosts = den.hosts.${system} or { };
  homes = den.homes.${system} or { };
in
if lib.hasSuffix "-darwin" system then
  let
    target = resolveTarget {
      entities = hosts;
      environment = "darwin";
      label = "Darwin configuration target";
      output = "darwinConfigurations";
    };
  in
  {
    darwin = target.outputName;
    entityNames.darwin = target.entityName;
  }
else if lib.hasSuffix "-linux" system then
  let
    nixosWsl = resolveTarget {
      entities = hosts;
      environment = "wsl";
      label = "NixOS-WSL configuration target";
      output = "nixosConfigurations";
    };
    linuxHome = resolveTarget {
      entities = homes;
      environment = "linux";
      label = "standalone Linux Home Manager target";
      output = "homeConfigurations";
    };
    wslHome = resolveTarget {
      entities = homes;
      environment = "wsl";
      label = "standalone WSL Home Manager target";
      output = "homeConfigurations";
    };
  in
  if linuxHome.outputName == wslHome.outputName then
    throw "standalone Linux and WSL entities for ${system} must declare distinct homeConfigurations targets"
  else
    {
      nixosWsl = nixosWsl.outputName;
      home = {
        linux = linuxHome.outputName;
        wsl = wslHome.outputName;
      };
      entityNames = {
        nixosWsl = nixosWsl.entityName;
        home = {
          linux = linuxHome.entityName;
          wsl = wslHome.entityName;
        };
      };
    }
else
  throw "configuration targets do not support system ${system}"
