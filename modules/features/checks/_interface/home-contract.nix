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
  username = entityContexts.linuxX86.username;

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

  factsFrom = context: {
    inherit (context)
      environment
      standalone
      system
      windows
      ;
    homeDirectory = context.homedir;
    registryPath = context.source;
  };
  standaloneEntry = context: environment: {
    name = "home:${context.home.${environment}}";
    value = (standalone context.home.${environment}) // {
      facts = factsFrom context.contexts.home.${environment};
    };
  };
  integratedWslEntry = context: {
    name = "nixos:${context.nixosWsl}";
    value = (integratedWsl context) // {
      facts = factsFrom context.contexts.nixosWsl;
    };
  };
  targets = builtins.listToAttrs [
    (standaloneEntry entityContexts.linuxX86 "linux")
    (standaloneEntry entityContexts.linuxAarch64 "linux")
    (standaloneEntry entityContexts.linuxX86 "wsl")
    (standaloneEntry entityContexts.linuxAarch64 "wsl")
    (integratedWslEntry entityContexts.linuxX86)
    (integratedWslEntry entityContexts.linuxAarch64)
    {
      name = "darwin:${entityContexts.darwin.darwin}";
      value = integratedDarwin // {
        facts = factsFrom entityContexts.darwin.contexts.darwin;
      };
    }
  ];

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
  validation = protocol.validateDiscovery { inherit contractNames; };
in
builtins.seq validation (
  pkgs.linkFarm "home-feature-contract" (
    map (path: {
      name = contractName path;
      path = loadContract path;
    }) contractFiles
  )
)
