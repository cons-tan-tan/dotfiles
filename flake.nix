{
  description = "constantan's home-manager configuration";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

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

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mozuku = {
      url = "github:t3tra-dev/MoZuKu";
    };

    codex-plugin-cc = {
      url = "github:openai/codex-plugin-cc";
      flake = false;
    };

    # Agent skills management
    agent-skills = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # External skill sources
    ast-grep-skill = {
      url = "github:ast-grep/claude-skill";
      flake = false;
    };

    agent-browser-skill = {
      url = "github:vercel-labs/agent-browser";
      flake = false;
    };

    agent-slack-skill = {
      url = "github:stablyai/agent-slack";
      flake = false;
    };

    anthropic-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };

    drawio-skill = {
      url = "github:jgraph/drawio-mcp";
      flake = false;
    };

    # Homebrew casks managed via Nix (macOS only)
    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      inputs.brew-api.follows = "brew-api";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };

  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      treefmt-nix,
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
      linuxHomedir = "/home/${username}";

      # Windows companion (WSL host only)
      windowsUsername = "zhouc";
      windowsHomedir = "/mnt/c/Users/${windowsUsername}";

      # All supported systems
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # pkgs builder shared across hosts
      mkPkgs = import ./nix/lib/mk-pkgs.nix { inherit inputs; };

      # Home Manager configuration builder for Linux/WSL hosts
      mkHost = import ./nix/lib/mk-host.nix {
        inherit inputs username windowsUsername windowsHomedir;
        homedir = linuxHomedir;
      };

      # nix-darwin configuration builder
      mkDarwin = import ./nix/lib/mk-darwin.nix {
        inherit inputs username;
        homedir = darwinHomedir;
      };

      # Linux/WSL host matrix: pair each architecture with each host kind
      linuxHostMatrix = [
        {
          hostKind = "linux";
          system = "x86_64-linux";
          hostFile = ./nix/hosts/linux.nix;
        }
        {
          hostKind = "linux";
          system = "aarch64-linux";
          hostFile = ./nix/hosts/linux.nix;
        }
        {
          hostKind = "wsl";
          system = "x86_64-linux";
          hostFile = ./nix/hosts/wsl.nix;
        }
        {
          hostKind = "wsl";
          system = "aarch64-linux";
          hostFile = ./nix/hosts/wsl.nix;
        }
      ];

      # Homedir for Linux/WSL apps (matches mkHost)
      linuxConfigName =
        { hostKind, system, ... }:
        "${username}@${hostKind}-${
          {
            "x86_64-linux" = "x86_64";
            "aarch64-linux" = "aarch64";
          }
          .${system}
        }";

      # Create treefmt wrapper
      mkTreefmtWrapper =
        pkgs:
        treefmt-nix.lib.mkWrapper pkgs {
          projectRootFile = "flake.nix";
          programs = {
            nixfmt = {
              enable = true;
              package = pkgs.nixfmt;
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

      # Apps for darwin host
      mkDarwinApps =
        system:
        let
          pkgs = mkPkgs system;
          treefmtWrapper = mkTreefmtWrapper pkgs;
        in
        {
          build = {
            type = "app";
            meta.description = "Build the nix-darwin configuration without activating it";
            program = toString (
              pkgs.writeShellScript "darwin-build" ''
                set -e
                echo "Building darwin configuration..."
                nix build .#darwinConfigurations.${darwinHostname}.system
                echo "Build successful! Run 'nix run .#switch' to apply."
              ''
            );
          };
          switch = {
            type = "app";
            meta.description = "Build and activate the nix-darwin configuration";
            program = toString (
              pkgs.writeShellScript "darwin-switch" ''
                set -e
                echo "Building and switching to darwin configuration..."
                sudo nix run nix-darwin -- switch --flake .#${darwinHostname}
              ''
            );
          };
          update = {
            type = "app";
            meta.description = "Update flake.lock to the latest input revisions";
            program = toString (
              pkgs.writeShellScript "flake-update" ''
                set -e
                echo "Updating flake.lock..."
                nix flake update
                echo "Done! Run 'nix run .#switch' to apply changes."
              ''
            );
          };
          fmt = {
            type = "app";
            meta.description = "Format the repository with treefmt";
            program = toString (
              pkgs.writeShellScript "treefmt-wrapper" ''
                exec ${treefmtWrapper}/bin/treefmt "$@"
              ''
            );
          };
        };

      # Apps for Linux/WSL hosts: switch auto-detects WSL vs native Linux at runtime
      mkLinuxApps =
        system:
        let
          pkgs = mkPkgs system;
          arch =
            {
              "x86_64-linux" = "x86_64";
              "aarch64-linux" = "aarch64";
            }
            .${system};
          treefmtWrapper = mkTreefmtWrapper pkgs;
          hmBin = "${home-manager.packages.${system}.default}/bin/home-manager";
        in
        {
          build = {
            type = "app";
            meta.description = "Build the Home Manager configuration without activating it (auto-detects WSL/Linux)";
            program = toString (
              pkgs.writeShellScript "home-manager-build" ''
                set -e
                if [[ -n "''${WSL_DISTRO_NAME:-}" ]]; then
                  target="${username}@wsl-${arch}"
                else
                  target="${username}@linux-${arch}"
                fi
                echo "Building Home Manager configuration: $target"
                nix build ".#homeConfigurations.\"$target\".activationPackage"
                echo "Build successful! Run 'nix run .#switch' to apply."
              ''
            );
          };
          switch = {
            type = "app";
            meta.description = "Build and activate the Home Manager configuration (auto-detects WSL/Linux)";
            program = toString (
              pkgs.writeShellScript "home-manager-switch" ''
                set -e
                if [[ -n "''${WSL_DISTRO_NAME:-}" ]]; then
                  target="${username}@wsl-${arch}"
                else
                  target="${username}@linux-${arch}"
                fi
                echo "Switching to Home Manager configuration: $target"
                ${hmBin} switch --flake ".#$target"
              ''
            );
          };
          update = {
            type = "app";
            meta.description = "Update flake.lock to the latest input revisions";
            program = toString (
              pkgs.writeShellScript "flake-update" ''
                set -e
                echo "Updating flake.lock..."
                nix flake update
                echo "Done! Run 'nix run .#switch' to apply changes."
              ''
            );
          };
          fmt = {
            type = "app";
            meta.description = "Format the repository with treefmt";
            program = toString (
              pkgs.writeShellScript "treefmt-wrapper" ''
                exec ${treefmtWrapper}/bin/treefmt "$@"
              ''
            );
          };
        };
    in
    {
      # macOS configuration with nix-darwin
      darwinConfigurations.${darwinHostname} = mkDarwin {
        hostname = darwinHostname;
        system = darwinSystem;
        hostFile = ./nix/hosts/darwin.nix;
      };

      # Linux/WSL configurations with standalone Home Manager
      homeConfigurations = lib.listToAttrs (
        map (entry: {
          name = linuxConfigName entry;
          value = mkHost entry;
        }) linuxHostMatrix
      );

      # Apps for common tasks
      apps = {
        ${darwinSystem} = mkDarwinApps darwinSystem;
        "x86_64-linux" = mkLinuxApps "x86_64-linux";
        "aarch64-linux" = mkLinuxApps "aarch64-linux";
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
