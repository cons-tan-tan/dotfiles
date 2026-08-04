{ inputs }:
let
  username = "constantan";
  linuxHome = "/home/${username}";
  windowsUsername = "zhouc";
  windowsHomedir = "/mnt/c/Users/${windowsUsername}";
  mkPkgs = import ../../lib/mk-pkgs.nix { inherit inputs; };
  configNames = import ../../lib/linux-config-name.nix { inherit username; };

  homeModules =
    {
      dotfilesDir ? "${linuxHome}/ghq/github.com/cons-tan-tan/dotfiles",
      hostKind,
      standalone ? true,
    }:
    [
      ../../modules/options.nix
      ../../modules/home
      ../../modules/linux
      {
        home = {
          inherit username;
          homeDirectory = linuxHome;
          stateVersion = "24.11";
        };
        my = {
          inherit dotfilesDir hostKind standalone;
        }
        // inputs.nixpkgs.lib.optionalAttrs (hostKind == "wsl") {
          windows = {
            username = windowsUsername;
            homedir = windowsHomedir;
          };
        };
      }
    ]
    ++ inputs.nixpkgs.lib.optionals (hostKind == "wsl") [ ../../modules/wsl ];

  standaloneEntries = [
    {
      hostKind = "linux";
      system = "x86_64-linux";
    }
    {
      hostKind = "linux";
      system = "aarch64-linux";
    }
    {
      hostKind = "wsl";
      system = "x86_64-linux";
    }
    {
      hostKind = "wsl";
      system = "aarch64-linux";
    }
  ];

  homeConfiguration =
    { hostKind, system }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs system;
      extraSpecialArgs = { inherit inputs; };
      modules = homeModules { inherit hostKind; };
    };

  darwinConfiguration = inputs.darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    specialArgs = {
      inherit username;
      homedir = "/Users/${username}";
    };
    modules = [
      { nixpkgs.pkgs = mkPkgs "aarch64-darwin"; }
      ../../modules/darwin/system.nix
      {
        system.primaryUser = username;
        users.users.${username}.home = "/Users/${username}";
      }
      inputs.home-manager.darwinModules.home-manager
      {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "hm-backup";
          extraSpecialArgs = { inherit inputs; };
          users.${username}.imports = [
            ../../modules/options.nix
            ../../modules/home
            ../../modules/darwin
            {
              home = {
                inherit username;
                homeDirectory = "/Users/${username}";
                stateVersion = "24.11";
              };
              my = {
                hostKind = "darwin";
                dotfilesDir = "/Users/${username}/ghq/github.com/cons-tan-tan/dotfiles";
                standalone = false;
              };
            }
          ];
        };
      }
    ];
  };

  wslConfiguration =
    system:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit username; };
      modules = [
        { nixpkgs.pkgs = mkPkgs system; }
        inputs.nixos-wsl.nixosModules.default
        ../../modules/nixos-wsl
        (
          { pkgs, ... }:
          {
            programs.zsh.enable = true;
            users.users.${username}.shell = pkgs.zsh;
            wsl.tarball.configPath = inputs.self.outPath;
            nix.channel.enable = false;
          }
        )
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "hm-backup";
            extraSpecialArgs = { inherit inputs; };
            users.${username}.imports = homeModules {
              hostKind = "wsl";
              dotfilesDir = inputs.self.outPath;
              standalone = false;
            };
          };
        }
      ];
    };
in
{
  darwinConfigurations.${username} = darwinConfiguration;

  homeConfigurations = inputs.nixpkgs.lib.listToAttrs (
    map (entry: {
      name = configNames.forHost entry;
      value = homeConfiguration entry;
    }) standaloneEntries
  );

  nixosConfigurations = {
    wsl = wslConfiguration "x86_64-linux";
    wsl-aarch64 = wslConfiguration "aarch64-linux";
  };
}
