{ pkgs, lib, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  home.packages = with pkgs; [
    # CLI tools
    curl
    mise
    chezmoi
    jq
    ripgrep
    fd
    fzf
    bat
    zoxide
    eza
    fastfetch
    protobuf
    redocly
    genact
    reuse
    ast-grep
    watchexec
    yazi
    ffmpeg

    # Editor
    neovim

    # Git
    ghq
    git-wt
    lefthook
    git-cliff
    pinact

    # Secret
    sops
    gopass
    trufflehog

    # AI Tools
    codex
    gemini-cli
    github-copilot-cli
    ccusage
    ccusage-codex
    agent-browser

    # Node.js
    ni
    pnpm
    # google-clasp

    # Python
    uv
    ruff
    ty
    basedpyright

    # Go
    go

    # Rust
    rustup

    # Nix
    nixd

    # R
    R

    # Japanese Language Server
    mozuku-lsp
  ];
}
