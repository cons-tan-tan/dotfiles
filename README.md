# dotfiles

Nix flake + Home Manager で Mac (aarch64-darwin) / WSL / Linux の開発環境を宣言的に管理する。
macOS は nix-darwin、Linux / WSL は standalone Home Manager。WSL ホストは Windows 側 (`/mnt/c`) の設定も書き出す。

## セットアップ

前提は Nix(flakes 有効)とこのリポジトリの clone だけ。GPG 鍵や secrets が無くても switch は完結する。

```sh
git clone https://github.com/cons-tan-tan/dotfiles.git ~/ghq/github.com/cons-tan-tan/dotfiles
cd ~/ghq/github.com/cons-tan-tan/dotfiles
nix run .#switch

# (任意・後からで良い) GPG 秘密鍵を導入して secrets を有効化
gpg --import <key>
nix run .#apply-secrets
```

## コマンド

| コマンド | 内容 |
| --- | --- |
| `nix run .#switch` | 構成のビルドと適用(ホスト自動判別) |
| `nix run .#build` | 適用せずビルドのみ |
| `nix run .#update` | flake.lock を更新 |
| `nix run .#update-pins` | バイナリ pin(`nix/pins/*.json`)を最新リリースへ同期 |
| `nix run .#fmt` | treefmt で整形 |
| `nix run .#apply-secrets` | sops secrets の復号・配置(鍵が無ければスキップ) |
| `nix run .#apply-winget` | Windows 側パッケージの適用(WSL のみ) |
| `nix run .#pptx -- <cmd>` | PPTX 変換ツールチェーン(markitdown / python-pptx / LibreOffice)入り環境でコマンド実行 |
| `nix run .#markdownlint` | リポジトリ管理の技術文書モードで markdownlint 実行 |
| `nix run .#textlint` | リポジトリ管理の日本語技術文書モードで textlint 実行 |

## 構成

```
flake.nix          # inputs / ホスト定義 / 出力の組み立て
nix/
├── lib/           # 構成ビルダーと共有設定生成器
├── modules/       # home (共通) / darwin / linux / wsl (+ windows companion)
├── hosts/         # ホストごとのモジュール束ね
├── overlays/      # 自前パッケージ (hcom / agent-slack / git-wt / ...)
├── pins/          # バイナリの version / hash (update-pins が更新)
└── apps/          # pptx / markdownlint / textlint / update-pins
agents/skills/     # ローカル agent skills
claude/            # Claude Code 設定
secrets/           # sops + GPG 暗号化 secrets (運用は secrets/README.md)
```

ssh は `~/.ssh/config`(Include 1 行)と `~/.ssh/config.d/` の断片を Nix が管理し、秘匿ホストは sops で暗号化して `apply-secrets` で復号する。
デバイス固有の設定は `~/.ssh/config.d/90-local.conf` のように手で置く。

## ライセンス

既定は CC0-1.0([LICENSE](LICENSE))。由来が異なるファイルは sidecar(`.license`)で明示(REUSE 準拠)。
