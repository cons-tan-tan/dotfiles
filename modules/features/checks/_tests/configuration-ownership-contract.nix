{
  darwinConfigurations,
  entityContexts,
  homeConfigurations,
  lib,
  nixosConfigurations,
  pkgs,
}:
let
  username = "constantan";
  linuxHomedir = "/home/${username}";
  standaloneSubjects = {
    "${username}@linux-aarch64" = {
      target = entityContexts.linuxAarch64.home.linux;
      system = "aarch64-linux";
    };
    "${username}@linux-x86_64" = {
      target = entityContexts.linuxX86.home.linux;
      system = "x86_64-linux";
    };
    "${username}@wsl-aarch64" = {
      target = entityContexts.linuxAarch64.home.wsl;
      system = "aarch64-linux";
    };
    "${username}@wsl-x86_64" = {
      target = entityContexts.linuxX86.home.wsl;
      system = "x86_64-linux";
    };
  };
  expectedStandalone = {
    "${username}@linux-aarch64" = "aarch64-linux";
    "${username}@linux-x86_64" = "x86_64-linux";
    "${username}@wsl-aarch64" = "aarch64-linux";
    "${username}@wsl-x86_64" = "x86_64-linux";
  };
  standaloneActual = lib.mapAttrs (
    _name: subject:
    if !(builtins.hasAttr subject.target homeConfigurations) then
      { exists = false; }
    else
      let
        configuration = homeConfigurations.${subject.target};
        home = configuration.config or { };
        activationPackage = configuration.activationPackage or null;
        activationPackageIsDerivation = lib.isDerivation activationPackage;
        services = lib.attrByPath [ "systemd" "user" "services" ] { } home;
        timers = lib.attrByPath [ "systemd" "user" "timers" ] { } home;
      in
      {
        exists = true;
        activationPackage = activationPackageIsDerivation;
        activationSystem = if activationPackageIsDerivation then activationPackage.system or null else null;
        username = lib.attrByPath [ "home" "username" ] null home;
        homeDirectory = lib.attrByPath [ "home" "homeDirectory" ] null home;
        nhProgramEnabled = lib.attrByPath [ "programs" "nh" "enable" ] null home;
        userCleanupEnabled = lib.attrByPath [ "programs" "nh" "clean" "enable" ] null home;
        userCleanupService = builtins.hasAttr "nh-clean" services;
        userCleanupTimer = builtins.hasAttr "nh-clean" timers;
        resultRootService = builtins.hasAttr "nh-clean-result-roots" services;
        resultRootTimer = builtins.hasAttr "nh-clean-result-roots" timers;
      }
  ) standaloneSubjects;
  standaloneExpected = lib.mapAttrs (
    name: system:
    let
      cleanupOwnedBySystem = lib.hasInfix "@wsl-" name;
    in
    {
      exists = true;
      activationPackage = true;
      activationSystem = system;
      username = username;
      homeDirectory = linuxHomedir;
      nhProgramEnabled = true;
      userCleanupEnabled = !cleanupOwnedBySystem;
      userCleanupService = !cleanupOwnedBySystem;
      userCleanupTimer = !cleanupOwnedBySystem;
      resultRootService = !cleanupOwnedBySystem;
      resultRootTimer = !cleanupOwnedBySystem;
    }
  ) expectedStandalone;

  expectedNixos = {
    wsl = "x86_64-linux";
    wsl-aarch64 = "aarch64-linux";
  };
  nixosSubjects = {
    wsl = entityContexts.linuxX86;
    wsl-aarch64 = entityContexts.linuxAarch64;
  };
  nixosActual = lib.mapAttrs (
    _name: subject:
    if !(builtins.hasAttr subject.nixosWsl nixosConfigurations) then
      { exists = false; }
    else
      let
        configuration = nixosConfigurations.${subject.nixosWsl};
        config = configuration.config or { };
        homeUsers = lib.attrByPath [ "home-manager" "users" ] { } config;
        homeExists = builtins.hasAttr subject.username homeUsers;
      in
      if !homeExists then
        {
          exists = true;
          inherit homeExists;
        }
      else
        let
          home = homeUsers.${subject.username};
          services = lib.attrByPath [ "systemd" "user" "services" ] { } home;
          timers = lib.attrByPath [ "systemd" "user" "timers" ] { } home;
        in
        {
          exists = true;
          inherit homeExists;
          system = lib.attrByPath [ "pkgs" "stdenv" "hostPlatform" "system" ] null configuration;
          useGlobalPkgs = lib.attrByPath [ "home-manager" "useGlobalPkgs" ] null config;
          useUserPackages = lib.attrByPath [ "home-manager" "useUserPackages" ] null config;
          backupFileExtension = lib.attrByPath [ "home-manager" "backupFileExtension" ] null config;
          username = lib.attrByPath [ "home" "username" ] null home;
          homeDirectory = lib.attrByPath [ "home" "homeDirectory" ] null home;
          systemCleanupEnabled = lib.attrByPath [ "programs" "nh" "clean" "enable" ] null config;
          homeCleanupEnabled = lib.attrByPath [ "programs" "nh" "clean" "enable" ] null home;
          homeCleanupService = builtins.hasAttr "nh-clean" services;
          homeCleanupTimer = builtins.hasAttr "nh-clean" timers;
          systemCleanupService = builtins.hasAttr "nh-clean" config.systemd.services;
          systemCleanupTimer = builtins.hasAttr "nh-clean" config.systemd.timers;
          systemResultRootService = builtins.hasAttr "nh-clean-result-roots" config.systemd.services;
          systemResultRootTimer = builtins.hasAttr "nh-clean-result-roots" config.systemd.timers;
        }
  ) nixosSubjects;
  nixosExpected = lib.mapAttrs (_: system: {
    exists = true;
    homeExists = true;
    inherit system;
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    username = username;
    homeDirectory = linuxHomedir;
    systemCleanupEnabled = false;
    homeCleanupEnabled = false;
    homeCleanupService = false;
    homeCleanupTimer = false;
    systemCleanupService = true;
    systemCleanupTimer = true;
    systemResultRootService = true;
    systemResultRootTimer = true;
  }) expectedNixos;

  darwinActual =
    if !(builtins.hasAttr entityContexts.darwin.darwin darwinConfigurations) then
      { exists = false; }
    else
      let
        configuration = darwinConfigurations.${entityContexts.darwin.darwin};
        config = configuration.config or { };
        homeUsers = lib.attrByPath [ "home-manager" "users" ] { } config;
        homeExists = builtins.hasAttr entityContexts.darwin.username homeUsers;
      in
      if !homeExists then
        {
          exists = true;
          inherit homeExists;
        }
      else
        let
          home = homeUsers.${entityContexts.darwin.username};
          agents = lib.attrByPath [ "launchd" "agents" ] { } home;
        in
        {
          exists = true;
          inherit homeExists;
          system = lib.attrByPath [ "pkgs" "stdenv" "hostPlatform" "system" ] null configuration;
          useGlobalPkgs = lib.attrByPath [ "home-manager" "useGlobalPkgs" ] null config;
          useUserPackages = lib.attrByPath [ "home-manager" "useUserPackages" ] null config;
          backupFileExtension = lib.attrByPath [ "home-manager" "backupFileExtension" ] null config;
          username = lib.attrByPath [ "home" "username" ] null home;
          homeDirectory = lib.attrByPath [ "home" "homeDirectory" ] null home;
          homeCleanupEnabled = lib.attrByPath [ "programs" "nh" "clean" "enable" ] null home;
          homeCleanupAgent = builtins.hasAttr "nh-clean" agents;
        };
  darwinExpected = {
    exists = true;
    homeExists = true;
    system = "aarch64-darwin";
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    username = username;
    homeDirectory = "/Users/${username}";
    homeCleanupEnabled = false;
    homeCleanupAgent = false;
  };

  actual = {
    standalone = standaloneActual;
    nixos = nixosActual;
    darwin = darwinActual;
  };
  expected = {
    standalone = standaloneExpected;
    nixos = nixosExpected;
    darwin = darwinExpected;
  };
in
assert lib.assertMsg (actual == expected) ''
  Configuration ownership contract mismatch:
  expected ${builtins.toJSON expected}
  actual ${builtins.toJSON actual}
'';
pkgs.runCommand "configuration-ownership-contract" { } ''touch "$out"''
