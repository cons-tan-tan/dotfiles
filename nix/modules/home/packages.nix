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
    # renovate # FIXME: nixpkgs-unstable で better-sqlite3 ビルド時に libtool が見つからずビルド失敗する
    typos
    typos-lsp
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
    nil

    # R
    R

    # Japanese Language Server
    mozuku-lsp
  ];
}
