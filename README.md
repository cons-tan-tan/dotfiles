# dotfiles

Nix flake + Home Manager で Mac (aarch64-darwin) / WSL / Linux の開発環境を
宣言的に管理するリポジトリ。macOS は nix-darwin、Linux / WSL は standalone
Home Manager を使う。WSL ホストは Windows 側 (`/mnt/c`) の設定も書き出す
(Windows companion レイヤ)。

## セットアップ(新デバイス)

前提は **Nix(flakes 有効)とこのリポジトリの clone だけ**。GPG 鍵や secrets
が無くても switch は完結する。

```shell
# 1. 所定のパスに clone する(nix registry / mkOutOfStoreSymlink がこのパスを前提にする)
git clone https://github.com/cons-tan-tan/dotfiles.git ~/ghq/github.com/cons-tan-tan/dotfiles
cd ~/ghq/github.com/cons-tan-tan/dotfiles

# 2. ビルド確認(任意)→ 適用
nix run .#build
nix run .#switch

# 3. (任意・後からで良い)GPG 秘密鍵を導入して secrets を有効化
gpg --import <key>
nix run .#secrets-apply
```

- `switch` は Linux / WSL を実行時に自動判別する。macOS では nix-darwin の
  switch になる(初回は `sudo` を求められる)。
- 適用後は flake registry に `dotfiles` が登録され、任意のディレクトリから
  `nix run dotfiles#<app>` が使える(clone 前は使えない)。
- 既存ファイルと衝突した場合は `.hm-backup` を残して置換される。

## よく使うコマンド

| コマンド | 内容 |
| --- | --- |
| `nix run .#switch` | 構成のビルドと適用(ホスト自動判別) |
| `nix run .#build` | 適用せずビルドのみ |
| `nix run .#update` | flake.lock を最新へ更新 |
| `nix run .#fmt` | treefmt でリポジトリ整形 |
| `nix run .#secrets-apply` | sops secrets の復号・配置(鍵が無ければスキップ) |
| `nix run .#winget-apply` | Windows 側パッケージの適用(WSL のみ、switch 後に実行) |
| `nix run dotfiles#pptx -- <cmd>` | PPTX ツール環境でコマンド実行 |
| `nix run dotfiles#markdownlint -- <files>` | markdownlint |
| `nix run dotfiles#textlint -- tech-jp <files>` | textlint(日本語技術文書) |
| `nix flake check --no-build --all-systems` | 全ホスト構成の評価検証(CI と同じ) |

## 構成

```
flake.nix              # inputs / ホスト定義 / 出力の組み立て
nix/
├── lib/               # ビルダーと共有定義
│   ├── mk-darwin.nix      # nix-darwin 構成ビルダー
│   ├── mk-host.nix        # standalone HM 構成ビルダー (Linux/WSL)
│   ├── mk-home-modules.nix# 両者で共有する HM モジュールリスト
│   ├── mk-pkgs.nix        # nixpkgs + overlays
│   ├── mk-apps.nix        # 共通 flake apps
│   └── settings/          # ホストと Windows companion で共有する設定生成器
├── modules/
│   ├── options.nix        # my.* options (hostKind / dotfilesDir / windows.*)
│   ├── home/              # 全ホスト共通の Home Manager 設定
│   ├── darwin/            # macOS 固有 (home レベル + system.nix)
│   ├── linux/             # Linux 固有
│   └── wsl/               # WSL 固有 + windows/ (Windows companion レイヤ)
├── hosts/             # darwin.nix / linux.nix / wsl.nix (モジュール束ね)
├── overlays/          # 自前パッケージ (hcom / agent-slack / git-wt / ...)
└── apps/              # pptx / markdownlint / textlint
agents/skills/         # ローカル agent skills (自動デプロイ)
claude/                # Claude Code 設定 (CLAUDE.md / rules / commands / ...)
secrets/               # sops + GPG 暗号化 secrets
```

設計の要点:

- ホスト種別などの構成パラメータは `my.*` options(`nix/modules/options.nix`)
  で配る。specialArgs は flake `inputs` のみ。
- Windows companion(WSL ホストが Windows 側に書き出す設定)は
  `nix/modules/wsl/windows/` の独立レイヤ。ホスト用と共有する設定値は
  `nix/lib/settings/` に置く。
- eval 時 IFD を全廃しているため、`nix flake check --no-build --all-systems`
  が単一の Linux ランナーで全システムを検証できる(CI もこれ)。

## ssh / secrets

`~/.ssh/config` 本体は `Include ~/.ssh/config.d/*.conf` の 1 行だけの定型
ファイルとして Nix が管理し、実際の設定は `~/.ssh/config.d/` の断片に置く。

1. switch すると `~/.ssh/config`(Include 1 行)と
   `~/.ssh/config.d/10-common.conf`(全環境共通の断片)が配置される。
   既存の手書き `~/.ssh/config` があった場合は黙って上書きせず
   `.hm-backup` に退避される(必要な内容は断片へ移すこと)
2. 秘匿ホスト(実 IP・アカウント名等)は `secrets/ssh-private.conf` に
   sops + GPG で暗号化してコミットし、`nix run .#secrets-apply` で
   `~/.ssh/config.d/50-private.conf` へ復号する。GPG 鍵が無いデバイスでは
   スキップされるだけで何も壊れない(Include はマッチしない glob を
   黙って無視する)
3. デバイス固有の一時設定が必要なら `~/.ssh/config.d/90-local.conf` の
   ように Nix 管理外の断片を手で置く(本体は編集しない)

secrets の運用は [secrets/README.md](secrets/README.md) を参照。鍵を伴う認証
(commit 署名・ssh)は GPG 鍵に寄せる方針で、sops の recipient も同じ鍵。

## 保守メモ

バイナリ系の pin(version / hash)は `nix/pins/*.json` に集約してあり、
**`nix run .#update-pins` で upstream の最新リリースへ自動同期**できる
(hcom / agent-slack / git-wt / codex config schema。hcom は flake input
`hcom-src` も同時に更新される)。差分を確認して `nix run .#build` を通して
からコミットする。

手で合わせる値は以下のみ:

| 値 | 場所 |
| --- | --- |
| `CLAUDE_CODE_SUBAGENT_MODEL` | `nix/lib/settings/claude.nix`(Sonnet 更新時) |
| Pi の `defaultModel` | `nix/modules/home/programs/pi.nix` |
| GPG 鍵(署名鍵 ID / sops recipient) | `nix/lib/settings/git.nix` / `.sops.yaml` |

## ライセンス

既定は CC0-1.0([LICENSE](LICENSE))。由来が異なるファイルは sidecar
(`.license`)で明示している(REUSE 準拠、CI で lint)。
