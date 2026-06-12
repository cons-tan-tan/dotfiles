# CLAUDE.md

Nix flake dotfiles。macOS (nix-darwin) / Linux / WSL (standalone Home Manager) を
管理し、WSL ホストは Windows 側 (/mnt/c) の設定も書き出す。

## 検証コマンド

| 目的 | コマンド |
| --- | --- |
| eval 検証 (CI と同一) | `nix flake check --no-build --all-systems` |
| フォーマット検証 | `nix run .#fmt -- --ci` |
| フォーマット適用 | `nix run .#fmt` |
| ライセンス検証 | `reuse lint` (devShell 内) |
| シェルスクリプトのテスト | `bats tests/` (devShell 内) |
| ビルド検証 (適用なし) | `nix run .#build` |

コミット前に最低限 eval 検証とフォーマット検証を通すこと。

## 壊しやすい暗黙の規約

- **eval 時 IFD 禁止**: derivation の出力を eval 時に `builtins.readFile` する
  と、異種プラットフォーム構成の評価 (`nix flake check --all-systems`) が
  壊れる。eval 時に読んでよいのは flake input とリポジトリ内のパスのみ。
  経緯: `nix/modules/home/agent-skills/default.nix` 冒頭の NOTE。
- **clone パスは固定**: `nix/lib/mk-home-modules.nix` が
  `~/ghq/github.com/cons-tan-tan/dotfiles` をハードコードし、
  `mkOutOfStoreSymlink` (claude/ 配下などの実体参照) がここに依存する。
- **REUSE 準拠**: 既定は CC0-1.0 (`REUSE.toml` の `**` 注釈)。由来が異なる
  ファイルだけ sidecar `.license` を置く。CI の reuse ジョブが強制する。
- **シェルスクリプトの新設は `writeShellApplication`** を使う (ビルド時
  shellcheck がかかる)。`writeShellScript` は歴史的経緯で残っているだけ。
  ロジックを持つスクリプトは `.sh` を分離して `builtins.readFile` で包み、
  `tests/*.bats` でテストする (例: `nix/apps/update-pins.sh`)。
- **home-manager で `force = true` は原則禁止**: 非管理ファイルとの衝突は
  backupFileExtension (`hm-backup`) で逃がす方針。

## 構造の要点

- `flake.nix` — inputs / ホスト定義 / 出力の組み立て。ホスト名と構成名の
  対応はコメント参照 (mkLinuxHostApps の $target と一致が必要)
- `nix/lib/` — 構成ビルダー (mk-pkgs / mk-host / mk-darwin) と共有設定生成器
  (`settings/`: claude / gh / git / gpg — 現ホストと Windows companion で共有)
- `nix/modules/options.nix` — `my.*` オプション (hostKind / dotfilesDir 等)。
  注意: darwin の system スコープでは参照不可 (HM スコープのみ)
- `nix/pins/*.json` — バイナリ pin。`nix run .#update-pins` で更新し、
  `nix run .#build` を通してからコミットする
- `secrets/` — sops + GPG。平文コミット厳禁。運用は `secrets/README.md`
- `claude/` — Claude Code の配備用設定 (このリポジトリ自体の開発設定ではない)。
  `claude/hooks/validate-gh-api.sh` はセキュリティゲートなので変更時は
  必ず `bats tests/validate-gh-api.bats` を回す

## コミット規約

Conventional Commits (feat / fix / refactor / docs / chore / build / ci / perf)。
日本語コメントは「何をするか」ではなく「なぜか」を書く。
