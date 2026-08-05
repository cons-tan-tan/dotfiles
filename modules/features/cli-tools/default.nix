{ ... }:
let
  tools = [
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
  features.cli-tools = {
    name = "feature/cli-tools";
    cli-tools = tools;

    homeManager =
      {
        cli-tools,
        lib,
        pkgs,
        ...
      }:
      let
        aggregated = import ./_lib/aggregate.nix { inherit lib pkgs; } cli-tools;
      in
      {
        home.packages = aggregated.nixHomePackages;
      };
  };
}
