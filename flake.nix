{
  description = "constantan's home-manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ai-tools = {
      url = "github:numtide/nix-ai-tools";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mozuku = {
      url = "github:comamoca/MoZuKu/feat/support-nix";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      ai-tools,
      treefmt-nix,
      mozuku,
      ...
    }:
    let
      lib = nixpkgs.lib;
      username = "constantan";

      # macOS configuration
      darwinSystem = "aarch64-darwin";
      darwinHomedir = "/Users/${username}";
      darwinHostname = "${username}";

      # Linux configuration
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      linuxHomedir = "/home/${username}";

      # All supported systems
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # Create pkgs with overlays
      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            (final: prev: {
              _ai-tools = ai-tools;
              mozuku-lsp = mozuku.packages.${system}.default;
            })
            (import ./nix/overlays)
          ];
        };

      # Create treefmt wrapper
      mkTreefmtWrapper =
        pkgs:
        treefmt-nix.lib.mkWrapper pkgs {
          projectRootFile = "flake.nix";
          programs = {
            nixfmt = {
              enable = true;
              package = pkgs.nixfmt-rfc-style;
            };
          };
          settings = {
            global.excludes = [
              ".git/**"
              "*.lock"
              "result"
            ];
          };
        };

      # Common apps for both Darwin and Linux
      mkCommonApps =
        system: homedir: hostname:
        let
          pkgs = mkPkgs system;
          isDarwin = pkgs.stdenv.isDarwin;
          treefmtWrapper = mkTreefmtWrapper pkgs;
        in
        {
          # Build configuration (platform-specific)
          build = {
            type = "app";
            program = toString (
              pkgs.writeShellScript (if isDarwin then "darwin-build" else "home-manager-build") ''
                set -e
                echo "Building ${if isDarwin then "darwin" else "Home Manager"} configuration..."
                nix build .#${
                  if isDarwin then
                    "darwinConfigurations.${hostname}.system"
                  else
                    "homeConfigurations.${username}.activationPackage"
                }
                echo "Build successful! Run 'nix run .#switch' to apply."
              ''
            );
          };

          # Apply configuration (platform-specific)
          switch = {
            type = "app";
            program = toString (
              pkgs.writeShellScript (if isDarwin then "darwin-switch" else "home-manager-switch") ''
                set -e
                echo "Building and switching to ${if isDarwin then "darwin" else "Home Manager"} configuration..."
                ${
                  if isDarwin then
                    "sudo nix run nix-darwin -- switch --flake .#${hostname}"
                  else
                    "${home-manager.packages.${system}.default}/bin/home-manager switch --flake .#${username}"
                }
              ''
            );
          };

          # Update flake.lock
          update = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "flake-update" ''
                set -e
                echo "Updating flake.lock..."
                nix flake update
                echo "Done! Run 'nix run .#switch' to apply changes."
              ''
            );
          };

          # Format code with treefmt
          fmt = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "treefmt-wrapper" ''
                exec ${treefmtWrapper}/bin/treefmt "$@"
              ''
            );
          };
        };

      # Helper to create Linux home configuration
      mkLinuxHomeConfig =
        linuxSystem:
        home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs linuxSystem;
          modules = [
            ./nix/modules/home
            {
              home = {
                username = username;
                homeDirectory = linuxHomedir;
              };
            }
          ];
        };
    in
    {
      # macOS configuration with nix-darwin
      darwinConfigurations.${darwinHostname} = nix-darwin.lib.darwinSystem {
        system = darwinSystem;
        modules = [
          # Darwin system configuration
          (import ./nix/modules/darwin/system.nix {
            pkgs = mkPkgs darwinSystem;
            lib = nixpkgs.lib;
            username = username;
            homedir = darwinHomedir;
          })

          # Home Manager integration for macOS
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = false;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {
              pkgs = mkPkgs darwinSystem;
            };
            home-manager.users.${username} =
              { pkgs, ... }:
              {
                imports = [
                  ./nix/modules/home
                  ./nix/modules/darwin
                ];
                home = {
                  username = username;
                  homeDirectory = darwinHomedir;
                };
              };
          }
        ];
      };

      # Linux configurations with standalone Home Manager
      homeConfigurations = {
        # x86_64-linux configuration
        ${username} = mkLinuxHomeConfig "x86_64-linux";
        # aarch64-linux configuration
        "${username}-aarch64" = mkLinuxHomeConfig "aarch64-linux";
      };

      # Apps for common tasks
      apps = {
        ${darwinSystem} = mkCommonApps darwinSystem darwinHomedir darwinHostname;
        "x86_64-linux" = mkCommonApps "x86_64-linux" linuxHomedir username;
        "aarch64-linux" = mkCommonApps "aarch64-linux" linuxHomedir username;
      };

      # Formatter for all systems
      formatter = lib.genAttrs systems (
        system:
        let
          pkgs = mkPkgs system;
        in
        mkTreefmtWrapper pkgs
      );
    };
}
