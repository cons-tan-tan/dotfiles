{
  config,
  inputs,
  lib,
  ...
}:
let
  username = "constantan";
  windows = {
    enable = true;
    username = "zhouc";
    homedir = "/mnt/c/Users/zhouc";
  };
  noWindows = {
    enable = false;
    username = null;
    homedir = null;
  };
  linuxHomedir = "/home/${username}";
  linuxSource = "${linuxHomedir}/ghq/github.com/cons-tan-tan/dotfiles";
  darwinHomedir = "/Users/${username}";
  darwinSource = "${darwinHomedir}/ghq/github.com/cons-tan-tan/dotfiles";
  hm = config.flake.modules.homeManager;
  inherit (import ./features/nixpkgs/_interface) mkPkgs mkOverlayPlan;
  linuxTargets =
    system:
    let
      arch = if system == "x86_64-linux" then "x86_64" else "aarch64";
      nixosWsl = if arch == "x86_64" then "wsl" else "wsl-aarch64";
      home = {
        linux = "${username}@linux-${arch}";
        wsl = "${username}@wsl-${arch}";
      };
      context = environment: outputName: standalone: {
        inherit
          system
          environment
          outputName
          standalone
          username
          ;
        homedir = linuxHomedir;
        source = if standalone then linuxSource else toString inputs.self.outPath;
        windows = if environment == "wsl" then windows else noWindows;
      };
    in
    {
      inherit
        nixosWsl
        home
        username
        linuxHomedir
        windows
        ;
      contexts = {
        nixosWsl = context "wsl" nixosWsl false;
        home = lib.mapAttrs (env: name: context env name true) home;
      };
    };
  darwinTarget = {
    darwin = "constantan";
    inherit username;
    windows = noWindows;
    contexts.darwin = {
      system = "aarch64-darwin";
      environment = "darwin";
      source = darwinSource;
      homedir = darwinHomedir;
      standalone = false;
      windows = noWindows;
      inherit username;
      outputName = "constantan";
    };
  };
  targets = {
    aarch64-darwin = darwinTarget;
    x86_64-linux = linuxTargets "x86_64-linux";
    aarch64-linux = linuxTargets "aarch64-linux";
  };
  homeIdentity = context: {
    home = {
      inherit username;
      homeDirectory = context.homedir;
    };
    dotfiles.platform = {
      inherit (context)
        environment
        source
        standalone
        windows
        ;
    };
  };
  # Integrated Home Manager shares the host package set. Keep allowances tied
  # to the selected user features instead of enabling every unfree package.
  hostPackages = system: { config, ... }: {
    nixpkgs.overlays = (mkOverlayPlan { inherit inputs system; }).overlays;
    nixpkgs.config.allowUnfreePredicate =
      package:
      lib.elem (lib.getName package) config.home-manager.users.${username}.dotfiles.unfreePackages;
  };
  nixosConfiguration =
    system:
    let
      target = targets.${system};
    in
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        inputs.nixos-wsl.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        config.flake.modules.nixos.wsl
        (hostPackages system)
        ({ pkgs, ... }: {
          networking.hostName = target.nixosWsl;
          wsl = {
            enable = true;
            defaultUser = username;
          };
          programs.zsh.enable = true;
          users.users.${username} = {
            name = username;
            home = linuxHomedir;
            isNormalUser = true;
            shell = pkgs.zsh;
            linger = true;
            extraGroups = [ "docker" ];
          };
          home-manager.users.${username}.imports = [
            hm.wsl
            (homeIdentity target.contexts.nixosWsl)
          ];
        })
      ];
    };
  standaloneHome =
    system: environment:
    let
      context = targets.${system}.contexts.home.${environment};
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = (mkPkgs { inherit inputs; }) system;
      modules = [
        (if environment == "wsl" then hm.standalone-wsl else hm.linux)
        (homeIdentity context)
        ({ config, ... }: {
          nixpkgs.config.allowUnfreePredicate =
            package: lib.elem (lib.getName package) config.dotfiles.unfreePackages;
        })
      ];
    };
in
{
  options.dotfiles.targets = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    readOnly = true;
    internal = true;
    description = "Configuration names and platform metadata used by local commands and checks.";
  };
  config = {
    dotfiles.targets = targets;
    flake = {
      nixosConfigurations = {
        wsl = nixosConfiguration "x86_64-linux";
        wsl-aarch64 = nixosConfiguration "aarch64-linux";
      };
      homeConfigurations = lib.listToAttrs (
        lib.concatMap
          (
            system:
            map
              (environment: {
                name = targets.${system}.home.${environment};
                value = standaloneHome system environment;
              })
              [
                "linux"
                "wsl"
              ]
          )
          [
            "x86_64-linux"
            "aarch64-linux"
          ]
      );
      darwinConfigurations.constantan = inputs.darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          inputs.home-manager.darwinModules.home-manager
          config.flake.modules.darwin.workstation
          (hostPackages "aarch64-darwin")
          ({ pkgs, ... }: {
            networking.hostName = "constantan";
            system.primaryUser = username;
            programs.zsh.enable = true;
            users.users.${username} = {
              name = username;
              home = darwinHomedir;
              shell = pkgs.zsh;
            };
            home-manager.users.${username}.imports = [
              hm.darwin
              (homeIdentity darwinTarget.contexts.darwin)
            ];
          })
        ];
      };
    };
  };
}
