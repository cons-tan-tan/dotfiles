{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  ax = inputs.ax.packages.${pkgs.stdenv.hostPlatform.system}.ax;
  cliTools = import ../../lib/settings/cli-tools.nix;
  sharedCliPackages = map (tool: pkgs.${tool.nixpkgsAttr}) (
    builtins.filter (tool: tool.linux == "home-packages") cliTools
  );
in
{
  home.packages =
    sharedCliPackages
    ++ (with pkgs; [
      # CLI tools
      # fzf のシェル統合は共有zsh設定の移行時に扱う。zoxide / starship は
      # programs.* モジュールでパッケージとzsh統合を管理する。
      fastfetch
      reuse
      watchexec
      yazi
      ffmpeg

      # Editor
      neovim

      # Git
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
      ax
      # Node.js
      # Zed remote が公式 glibc バイナリへフォールバックするのを避ける。
      nodejs
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
      shellfirm
    ])
    ++ lib.optionals config.dotfiles.hcom.enable [
      pkgs.dotfilesPackages.hcom.package
    ];
}
