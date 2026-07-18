{ config, pkgs, ... }:
{
  # agent-browser の既定値 ($XDG_RUNTIME_DIR/agent-browser) は Codex の
  # filesystem sandbox から書けないため、許可済みの ~/.cache 配下へ置く。
  home.sessionVariables.AGENT_BROWSER_SOCKET_DIR =
    "${config.home.homeDirectory}/.cache/agent-browser/sockets";

  home.packages = with pkgs; [
    # CLI tools
    # NOTE: fzf / zoxide / starship のシェル統合 (eval "$(... init zsh)") は
    # 意図的に Nix 管理外の ~/.zshrc に手書きしている (シェル init はまだ
    # HM 管理に移行していない)。HM の programs.fzf 等を enable しても
    # programs.zsh が無効な現状では init が配備されないため、ここでは
    # パッケージ導入のみ行う。
    jq
    ripgrep
    fd
    fzf
    bat
    zoxide
    eza
    fastfetch
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
    git-cliff
    pinact

    # Secret
    sops
    gopass
    trufflehog

    # AI Tools
    gemini-cli
    github-copilot-cli
    ccusage
    agent-browser
    agent-slack
    difit
    hcom
    shellfirm

    # Node.js
    ni
    pnpm

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

    # Japanese Language Server
    mozuku-lsp
  ];
}
