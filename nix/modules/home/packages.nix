{ pkgs, lib, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  home.packages = with pkgs; [
    # CLI tools
    mise
    chezmoi
    jq
    ripgrep
    fd
    fzf
    bat
    fastfetch
    protobuf
    redocly

    # Git
    git
    gh
    ghq
    lefthook
    git-cliff

    # Secret
    sops
    gopass
    trufflehog

    # AI Tools
    claude-code
    codex
    gemini-cli
    github-copilot-cli
    ccusage
    ccusage-codex

    # Google Cloud
    google-cloud-sdk

    # Node.js
    ni
    pnpm
    google-clasp

    # Python
    uv
    ruff

    # Go
    go

    # Terraform
    pike
  ];
}
