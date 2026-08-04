{
  den,
  inputs,
  ...
}:
let
  cliTools = [
    {
      id = "reuse";
      nix = {
        route = "home-packages";
        nixpkgsAttr = "reuse";
      };
    }
    {
      id = "rg";
      nix = {
        route = "home-packages";
        nixpkgsAttr = "ripgrep";
      };
      winget = {
        packageId = "BurntSushi.ripgrep.MSVC";
        description = "ripgrep";
      };
    }
    {
      id = "fd";
      nix = {
        route = "home-packages";
        nixpkgsAttr = "fd";
      };
      winget = {
        packageId = "sharkdp.fd";
        description = "fd";
      };
    }
    {
      id = "bat";
      nix = {
        route = "home-packages";
        nixpkgsAttr = "bat";
      };
      winget = {
        packageId = "sharkdp.bat";
        description = "bat";
      };
    }
    {
      id = "eza";
      nix = {
        route = "home-packages";
        nixpkgsAttr = "eza";
      };
      winget = {
        packageId = "eza-community.eza";
        description = "eza";
      };
    }
    {
      id = "jq";
      nix = {
        route = "home-packages";
        nixpkgsAttr = "jq";
      };
      winget = {
        packageId = "jqlang.jq";
        description = "jq";
      };
    }
    {
      id = "ast-grep";
      nix = {
        route = "home-packages";
        nixpkgsAttr = "ast-grep";
      };
      winget = {
        packageId = "ast-grep.ast-grep";
        description = "ast-grep";
      };
    }
    {
      id = "fzf";
      nix = {
        route = "home-packages";
        nixpkgsAttr = "fzf";
      };
      winget = {
        packageId = "junegunn.fzf";
        description = "fzf";
      };
    }
  ];
in
{
  # mozuku-lsp は cabocha / crfpp の C++ チェーンごと source build になり、
  # binary cache にない。nixpkgs を follows するとその更新ごとに再ビルド
  # されるため、upstream の pin を version authority とする。
  flake-file.inputs.mozuku.url = "github:t3tra-dev/MoZuKu";

  flake-file.inputs.ax = {
    # The CLI and the skill use the same input as their version authority.
    url = "github:yusukebe/ax/v0.1.23";
    inputs.bun2nix.follows = "bun2nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  features.packages = {
    name = "feature/packages";
    includes = [
      (den.batteries.unfree [
        "github-copilot-cli"
      ])
    ];
    cli-tools = cliTools;
    homeManager =
      {
        cli-tools,
        lib,
        pkgs,
        ...
      }:
      let
        ax = inputs.ax.packages.${pkgs.stdenv.hostPlatform.system}.ax;
        aggregated = import ./_lib/aggregate-cli-tools.nix { inherit lib pkgs; } cli-tools;
      in
      {
        home.packages =
          aggregated.nixHomePackages
          ++ (with pkgs; [
            fastfetch
            watchexec
            yazi
            ffmpeg
            neovim
            git-cliff
            pinact
            zizmor
            sops
            gopass
            trufflehog
            gemini-cli
            github-copilot-cli
            ccusage
            ax
            # Avoid Zed remote falling back to its upstream glibc binary.
            nodejs
            ni
            pnpm
            uv
            ruff
            ty
            basedpyright
            go
            rustup
            nixd
            mozuku-lsp
          ])
          ++ (with pkgs.dotfilesPackages; [
            agent-browser
            agent-slack
            difit
            gha-lint
            shellfirm
          ]);
      };
  };
}
