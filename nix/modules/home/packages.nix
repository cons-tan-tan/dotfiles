{ pkgs, ... }:
{
  home.packages =
    (with pkgs; [
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
    ])
    ++ (with pkgs.dotfilesPackages; [
      agent-browser
      agent-slack
      difit
      hcom.package
      shellfirm
    ]);
}
