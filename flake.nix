{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
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
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      home-manager,
      ai-tools,
      treefmt-nix,
      ...
    }:
    let
      username = "constantan";
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
          overlays = [
            (final: prev: {
              _ai-tools = ai-tools;
            })
            (import ./nix/overlays)
          ];
        };
        modules = [
          ./nix/modules/home
          {
            home = {
              username = username;
              homeDirectory = "/home/${username}";
            };
          }
        ];
      };

      apps = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          treefmtWrapper = treefmt-nix.lib.mkWrapper pkgs {
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
        in
        {
          fmt = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "treefmt-wrapper" ''
                exec ${treefmtWrapper}/bin/treefmt "$@"
              ''
            );
          };

          switch = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "home-manager-switch" ''
                set -e
                echo "Building and switching to Home Manager configuration..."
                ${home-manager.packages.${system}.default}/bin/home-manager switch --flake .#${username}
              ''
            );
          };

          build = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "home-manager-build" ''
                set -e
                echo "Building Home Manager configuration..."
                nix build .#homeConfigurations.${username}.activationPackage
                echo "Build successful! Run 'nix run .#switch' to apply."
              ''
            );
          };
        }
      );

      formatter = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
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
        }
      );
    };
}
