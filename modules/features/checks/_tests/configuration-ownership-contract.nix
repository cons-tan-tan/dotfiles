{
  darwinConfigurations,
  entityContexts,
  homeConfigurations,
  lib,
  nixosConfigurations,
  pkgs,
}:
let
  standaloneSubject = context: environment: {
    name = "home:${context.home.${environment}}";
    value = {
      target = context.home.${environment};
      context = context.contexts.home.${environment};
    };
  };
  standaloneSubjects = builtins.listToAttrs [
    (standaloneSubject entityContexts.linuxX86 "linux")
    (standaloneSubject entityContexts.linuxAarch64 "linux")
    (standaloneSubject entityContexts.linuxX86 "wsl")
    (standaloneSubject entityContexts.linuxAarch64 "wsl")
  ];
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
      in
      {
        exists = true;
        activationPackage = activationPackageIsDerivation;
        activationSystem = if activationPackageIsDerivation then activationPackage.system or null else null;
        username = lib.attrByPath [ "home" "username" ] null home;
        homeDirectory = lib.attrByPath [ "home" "homeDirectory" ] null home;
      }
  ) standaloneSubjects;
  standaloneExpected = lib.mapAttrs (_name: subject: {
    exists = true;
    activationPackage = true;
    activationSystem = subject.context.system;
    username = subject.context.userName;
    homeDirectory = subject.context.homedir;
  }) standaloneSubjects;

  nixosSubject = context: {
    name = "nixos:${context.nixosWsl}";
    value = context;
  };
  nixosSubjects = builtins.listToAttrs [
    (nixosSubject entityContexts.linuxX86)
    (nixosSubject entityContexts.linuxAarch64)
  ];
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
        }
  ) nixosSubjects;
  nixosExpected = lib.mapAttrs (_: subject: {
    exists = true;
    homeExists = true;
    system = subject.contexts.nixosWsl.system;
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    username = subject.username;
    homeDirectory = subject.contexts.nixosWsl.homedir;
  }) nixosSubjects;

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
        };
  darwinExpected = {
    exists = true;
    homeExists = true;
    system = entityContexts.darwin.contexts.darwin.system;
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    username = entityContexts.darwin.contexts.darwin.username;
    homeDirectory = entityContexts.darwin.contexts.darwin.homedir;
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
