{
  entityContexts,
  flake,
  lib,
  pkgs,
}:
let
  username = "constantan";
  subjectUsername = entityContexts.linuxX86.username;
  standaloneLinuxResult = flake.homeConfigurations.${entityContexts.linuxX86.home.linux};
  standaloneLinux = standaloneLinuxResult.config;
  standaloneWsl = flake.homeConfigurations.${entityContexts.linuxX86.home.wsl}.config;
  integratedWslSystem = flake.nixosConfigurations.${entityContexts.linuxX86.nixosWsl}.config;
  integratedWsl = integratedWslSystem.home-manager.users.${subjectUsername};
  darwinResult = flake.darwinConfigurations.${entityContexts.darwin.darwin};
  darwinSystem = darwinResult.config;
  darwin = darwinSystem.home-manager.users.${entityContexts.darwin.username};

  mkContract =
    {
      actual,
      expected,
      name,
    }:
    assert lib.assertMsg (actual == expected) ''
      ${name} Platform contract mismatch:
      expected ${builtins.toJSON expected}
      actual ${builtins.toJSON actual}
    '';
    pkgs.runCommand "${name}-platform-contract" { } ''touch "$out"'';

  contractSuffix = ".platform-contract.nix";
  contractFiles = builtins.filter (
    path: lib.hasSuffix contractSuffix (baseNameOf path) && lib.hasInfix "/_tests/" (toString path)
  ) (lib.filesystem.listFilesRecursive ../.);
  contractName = path: lib.removeSuffix contractSuffix (baseNameOf path);
  contractNames = map contractName contractFiles;
  expectedContractNames = import ./platform-contracts.nix;
  duplicateNames = builtins.filter (
    name: builtins.length (builtins.filter (candidate: candidate == name) contractNames) > 1
  ) (lib.unique contractNames);
  context = {
    inherit
      darwin
      darwinResult
      darwinSystem
      integratedWsl
      integratedWslSystem
      lib
      standaloneLinux
      standaloneLinuxResult
      standaloneWsl
      username
      ;
  };
  loadContract =
    path:
    let
      declaration = import path;
      functionArgs = if builtins.isFunction declaration then builtins.functionArgs declaration else { };
      missingRequiredArgs = builtins.filter (
        name: !functionArgs.${name} && !builtins.hasAttr name context
      ) (builtins.attrNames functionArgs);
      name = contractName path;
      descriptor =
        if builtins.isFunction declaration then
          declaration (builtins.intersectAttrs functionArgs context)
        else
          declaration;
      descriptorNames = if builtins.isAttrs descriptor then builtins.attrNames descriptor else [ ];
    in
    if missingRequiredArgs != [ ] then
      throw "${toString path} requires unavailable Platform contract arguments: ${builtins.toJSON missingRequiredArgs}"
    else if !builtins.isAttrs descriptor then
      throw "${toString path} must return a Platform contract descriptor"
    else if
      descriptorNames != [
        "actual"
        "expected"
      ]
    then
      throw "${toString path} Platform contract descriptor must contain exactly actual and expected"
    else
      mkContract {
        inherit (descriptor) actual expected;
        inherit name;
      };
  validation =
    if contractFiles == [ ] then
      throw "No Feature-owned Platform contracts were discovered"
    else if duplicateNames != [ ] then
      throw "Duplicate Feature-owned Platform contract names: ${builtins.toJSON duplicateNames}"
    else if lib.sort builtins.lessThan contractNames != expectedContractNames then
      throw ''
        Feature-owned Platform contract ledger mismatch:
        expected ${builtins.toJSON expectedContractNames}
        actual ${builtins.toJSON (lib.sort builtins.lessThan contractNames)}
      ''
    else
      null;
in
builtins.seq validation (
  pkgs.linkFarm "platform-feature-contract" (
    map (path: {
      name = contractName path;
      path = loadContract path;
    }) contractFiles
  )
)
