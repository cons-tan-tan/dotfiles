{
  flake,
  inputs,
  lib,
  pkgs,
}:
let
  username = "constantan";
  sort = lib.sort builtins.lessThan;
  legacy = import ./fixtures/legacy-configurations.nix { inherit inputs; };

  differencePaths =
    path: left: right:
    if builtins.isAttrs left && builtins.isAttrs right then
      let
        keys = lib.unique (builtins.attrNames left ++ builtins.attrNames right);
      in
      lib.concatMap (
        key:
        if left ? ${key} && right ? ${key} then
          differencePaths (path ++ [ key ]) left.${key} right.${key}
        else
          [ (path ++ [ key ]) ]
      ) keys
    else if left == right then
      [ ]
    else
      [ path ];

  describeHomeConfig =
    config:
    {
      inherit (config.home) username homeDirectory;
      hostKind = config.my.hostKind;
      dotfilesDir = config.my.dotfilesDir;
      standalone = config.my.standalone;
      windows = config.my.windows;
      nhCleanup = {
        inherit (config.programs.nh.clean) dates enable extraArgs;
      };
      programs = {
        git = config.programs.git.enable;
        homeManager = config.programs.home-manager.enable;
        nh = config.programs.nh.enable;
      };
      stateVersion = config.home.stateVersion;
    }
    // lib.optionalAttrs (config.my.hostKind != "linux") {
      homeFiles = sort (builtins.attrNames config.home.file);
      homePackages = sort (map lib.getName config.home.packages);
    };

  linuxHome = outputs: name: outputs.homeConfigurations.${name}.config;
  linuxShellTransition =
    name:
    let
      old = linuxHome legacy name;
      new = linuxHome flake name;
      oldFiles = sort (builtins.attrNames old.home.file);
      newFiles = sort (builtins.attrNames new.home.file);
      oldPackages = sort (map lib.getName old.home.packages);
      newPackages = sort (map lib.getName new.home.packages);
      added = before: after: builtins.filter (item: !(lib.elem item before)) after;
    in
    {
      legacyEnabled = old.programs.zsh.enable;
      denEnabled = new.programs.zsh.enable;
      addedFiles = added oldFiles newFiles;
      removedFiles = added newFiles oldFiles;
      addedPackages = added oldPackages newPackages;
      removedPackages = added newPackages oldPackages;
    };
  expectedLinuxShellTransition = {
    legacyEnabled = false;
    denEnabled = true;
    addedFiles = [
      "./.zprofile"
      "./.zshenv"
      "./.zshrc"
    ];
    removedFiles = [ ];
    addedPackages = [
      "nix-zsh-completions"
      "zsh"
    ];
    removedPackages = [ ];
  };

  describeDarwinBatteryTransition =
    outputs:
    let
      config = outputs.darwinConfigurations.${username}.config;
      shell = config.users.users.${username}.shell;
    in
    {
      hostName = config.networking.hostName;
      userShell = if shell == null then null else lib.getName shell;
      zshEnabled = config.programs.zsh.enable;
    };

  describeStandaloneHome =
    outputs: name:
    let
      result = outputs.homeConfigurations.${name};
    in
    {
      config = describeHomeConfig result.config;
      difit = result.pkgs.dotfilesPackages.difit.drvPath;
    };

  describeWsl =
    outputs: name:
    let
      result = outputs.nixosConfigurations.${name};
      config = result.config;
      home = config.home-manager.users.${username};
    in
    {
      system = result.pkgs.stdenv.hostPlatform.system;
      defaultUser = config.wsl.defaultUser;
      hostname = config.wsl.wslConf.network.hostname;
      tarballConfigPath = toString config.wsl.tarball.configPath;
      user = {
        inherit (config.users.users.${username}) extraGroups;
        shell = config.users.users.${username}.shell.drvPath;
      };
      homeManager = {
        inherit (config.home-manager) backupFileExtension useGlobalPkgs useUserPackages;
      };
      home = describeHomeConfig home;
      difit = result.pkgs.dotfilesPackages.difit.drvPath;
    };

  describeDarwin =
    outputs:
    let
      result = outputs.darwinConfigurations.${username};
      config = result.config;
      home = config.home-manager.users.${username};
    in
    {
      system = result.pkgs.stdenv.hostPlatform.system;
      primaryUser = config.system.primaryUser;
      userHome = config.users.users.${username}.home;
      homeManager = {
        inherit (config.home-manager) backupFileExtension useGlobalPkgs useUserPackages;
      };
      home = describeHomeConfig home;
      difit = result.pkgs.dotfilesPackages.difit.drvPath;
      watchexec = result.pkgs.watchexec.drvPath;
    };

  describeOutputs = outputs: {
    names = {
      darwin = sort (builtins.attrNames outputs.darwinConfigurations);
      home = sort (builtins.attrNames outputs.homeConfigurations);
      nixos = sort (builtins.attrNames outputs.nixosConfigurations);
    };
    homes = lib.genAttrs [
      "${username}@linux-x86_64"
      "${username}@linux-aarch64"
      "${username}@wsl-x86_64"
      "${username}@wsl-aarch64"
    ] (describeStandaloneHome outputs);
    wsl = lib.genAttrs [
      "wsl"
      "wsl-aarch64"
    ] (describeWsl outputs);
    darwin = describeDarwin outputs;
  };

  actual = {
    outputs = describeOutputs flake;
    hostnameTransition = {
      legacy = map (name: legacy.nixosConfigurations.${name}.config.networking.hostName) [
        "wsl"
        "wsl-aarch64"
      ];
      den = map (name: flake.nixosConfigurations.${name}.config.networking.hostName) [
        "wsl"
        "wsl-aarch64"
      ];
    };
    linuxShellTransition = lib.genAttrs [
      "${username}@linux-x86_64"
      "${username}@linux-aarch64"
    ] linuxShellTransition;
    darwinBatteryTransition = {
      legacy = describeDarwinBatteryTransition legacy;
      den = describeDarwinBatteryTransition flake;
    };
  };
  expected = {
    outputs = describeOutputs legacy;
    hostnameTransition = {
      legacy = [
        "nixos"
        "nixos"
      ];
      den = [
        "wsl"
        "wsl-aarch64"
      ];
    };
    # user-shell intentionally owns shell enablement at both OS and HM scope.
    # The old Linux-only Home Manager constructor did not enable zsh itself.
    linuxShellTransition = lib.genAttrs [
      "${username}@linux-x86_64"
      "${username}@linux-aarch64"
    ] (_: expectedLinuxShellTransition);
    # The hostname and user-shell Batteries now own the corresponding Darwin
    # settings that were left unset by the constructor topology.
    darwinBatteryTransition = {
      legacy = {
        hostName = null;
        userShell = null;
        zshEnabled = true;
      };
      den = {
        hostName = username;
        userShell = "zsh";
        zshEnabled = true;
      };
    };
  };
in
assert lib.assertMsg (actual == expected) ''
  Den output differs from the frozen constructor fixture:
  differing paths ${builtins.toJSON (differencePaths [ ] expected actual)}
  shell transition ${builtins.toJSON actual.linuxShellTransition}
'';
pkgs.runCommand "den-legacy-parity-tests" { } ''touch "$out"''
