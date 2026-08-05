{
  entityContexts,
  flake,
  inputs,
  lib,
  pkgs,
  repoRoot,
}:
let
  protocol = import ../_lib/home-contract-protocol.nix { inherit lib; };
  username = "constantan";
  canonicalLinux = "/home/${username}/ghq/github.com/cons-tan-tan/dotfiles";
  canonicalDarwin = "/Users/${username}/ghq/github.com/cons-tan-tan/dotfiles";

  standalone = target: {
    config = flake.homeConfigurations.${target}.config;
    inherit (flake.homeConfigurations.${target}) pkgs;
  };
  integratedWsl = context: {
    config =
      flake.nixosConfigurations.${context.nixosWsl}.config.home-manager.users.${context.username};
    inherit (flake.nixosConfigurations.${context.nixosWsl}) pkgs;
  };
  integratedDarwin = {
    config =
      flake.darwinConfigurations.${entityContexts.darwin.darwin}.config.home-manager.users.${entityContexts.darwin.username};
    inherit (flake.darwinConfigurations.${entityContexts.darwin.darwin}) pkgs;
  };

  withFacts = entry: facts: entry // { inherit facts; };
  targets = {
    "${username}@linux-x86_64" = withFacts (standalone entityContexts.linuxX86.home.linux) {
      environment = "linux";
      homeDirectory = "/home/${username}";
      registryPath = canonicalLinux;
      system = "x86_64-linux";
    };
    "${username}@linux-aarch64" = withFacts (standalone entityContexts.linuxAarch64.home.linux) {
      environment = "linux";
      homeDirectory = "/home/${username}";
      registryPath = canonicalLinux;
      system = "aarch64-linux";
    };
    "${username}@wsl-x86_64" = withFacts (standalone entityContexts.linuxX86.home.wsl) {
      environment = "wsl";
      homeDirectory = "/home/${username}";
      registryPath = canonicalLinux;
      system = "x86_64-linux";
    };
    "${username}@wsl-aarch64" = withFacts (standalone entityContexts.linuxAarch64.home.wsl) {
      environment = "wsl";
      homeDirectory = "/home/${username}";
      registryPath = canonicalLinux;
      system = "aarch64-linux";
    };
    wsl = withFacts (integratedWsl entityContexts.linuxX86) {
      environment = "wsl";
      homeDirectory = "/home/${username}";
      registryPath = toString inputs.self.outPath;
      system = "x86_64-linux";
    };
    wsl-aarch64 = withFacts (integratedWsl entityContexts.linuxAarch64) {
      environment = "wsl";
      homeDirectory = "/home/${username}";
      registryPath = toString inputs.self.outPath;
      system = "aarch64-linux";
    };
    darwin = withFacts integratedDarwin {
      environment = "darwin";
      homeDirectory = "/Users/${username}";
      registryPath = canonicalDarwin;
      system = "aarch64-darwin";
    };
  };

  mkContract =
    {
      describe,
      expected,
      name,
    }:
    let
      actualByTarget = lib.mapAttrs (_: target: describe target) targets;
      expectedByTarget = lib.mapAttrs (_: target: expected target.facts) targets;
    in
    assert lib.assertMsg (actualByTarget == expectedByTarget) ''
      ${name} mismatch:
      expected ${builtins.toJSON expectedByTarget}
      actual ${builtins.toJSON actualByTarget}
    '';
    pkgs.runCommand name { } ''touch "$out"'';

  contractSuffix = ".home-contract.nix";
  contractFiles = builtins.filter (
    path: lib.hasSuffix contractSuffix (baseNameOf path) && lib.hasInfix "/_tests/" (toString path)
  ) (lib.filesystem.listFilesRecursive (repoRoot + "/modules/features"));
  contractName = path: lib.removeSuffix contractSuffix (baseNameOf path);
  contractNames = map contractName contractFiles;
  expectedContractNames = import ../_data/home-contracts.nix;
  context = {
    inherit
      inputs
      lib
      username
      ;
  };
  loadContract =
    path:
    protocol.loadContract {
      inherit context;
      contractName = contractName path;
      declaration = import path;
      inherit mkContract;
      source = toString path;
    };
  validation = protocol.validateLedger {
    inherit contractNames expectedContractNames;
  };
in
builtins.seq validation (
  pkgs.linkFarm "home-feature-contract" (
    map (path: {
      name = contractName path;
      path = loadContract path;
    }) contractFiles
  )
)
