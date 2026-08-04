{
  den,
  inputs,
  ...
}:
let
  cliTools = import ./_lib/cli-tools.nix;
in
{
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
    homeManager =
      {
        pkgs,
        ...
      }:
      let
        ax = inputs.ax.packages.${pkgs.stdenv.hostPlatform.system}.ax;
        sharedCliPackages = map (tool: pkgs.${tool.nixpkgsAttr}) (
          builtins.filter (tool: tool.linux == "home-packages") cliTools
        );
      in
      {
        home.packages =
          sharedCliPackages
          ++ (with pkgs; [
            fastfetch
            reuse
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
