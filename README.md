# dotfiles

Nix flake + Home ManagerでMac (aarch64-darwin) / WSL / Linuxの開発環境を宣言的に管理する。
macOSはnix-darwin、NixOS-WSLはNixOS + Home Manager、その他のLinux / Ubuntu WSLはstandalone Home Managerを使う。WSLホストはWindows側 (`/mnt/c`) の設定も書き出す。

## セットアップ

前提はNix(flakes有効)とこのリポジトリのcloneだけ。GPG鍵やsecretsが無くてもswitchは完結する。
NixOS以外では、初回にOS側のNix daemon設定を同期して、NumTide cacheとtrusted userを有効にする。
`apply-nix-settings`は`/etc/nix/nix.conf`が同じディレクトリの`nix.custom.conf`をincludeしている環境向け。
未対応のNix installでは停止するので、includeを追加するか、daemon設定を別管理するか、この手順をskipしてcache / trusted userなしで`switch`に進む。

```sh
git clone https://github.com/cons-tan-tan/dotfiles.git ~/ghq/github.com/cons-tan-tan/dotfiles
cd ~/ghq/github.com/cons-tan-tan/dotfiles
nix run .#apply-nix-settings

# 表示された案内に従って Nix daemon を再起動する
# macOS: sudo launchctl kickstart -k system/org.nixos.nix-daemon
# Linux/Ubuntu WSL(systemd): sudo systemctl restart nix-daemon.service

nix run .#switch

# (任意・後からで良い) GPG 秘密鍵を導入して secrets を有効化
gpg --import <key>
nix run .#apply-secrets
```

### NixOS-WSL

既存のflakes対応Nix環境から、Home Manager設定を含むWSLイメージを生成する。

```sh
sudo nix run .#nixosConfigurations.wsl.config.system.build.tarballBuilder
```

生成された`nixos.wsl`をWindows側の任意のディレクトリへコピーし、そのディレクトリで次を実行する。

```powershell
wsl --install --from-file .\nixos.wsl --name NixOS
```

必要なら初回起動後に`passwd`でパスワードを設定する。以後は通常のclone先で`nix run .#switch`を使い、`apply-nix-settings`は実行しない。Windows on Armの構成名は`wsl-aarch64`。

## コマンド

| コマンド | 内容 |
| --- | --- |
| `nix run .#switch` | 構成のビルドと適用(NixOS-WSL / Home Managerを自動判別) |
| `nix run .#build` | ホスト構成を適用せずビルドのみ |
| `nix run .#update` | flake.lock を更新 |
| `nix run .#update-pins` | すべての更新対象をupstreamの最新状態へ同期 |
| `nix run .#update-pins -- <target>` | 指定したtargetのみ同期。target一覧は`nix run .#update-pins -- --help`で表示 |
| `nix run .#update-pins -- --check <target>` | 更新・build・検証を本番と同じ経路で実行し、管理fileは終了時に復元 |
| `nix run .#update-pins -- --jobs 4 <target>` | release assetのprefetchを最大4並列で実行 |
| `nix run .#fmt` | treefmt で整形 |
| `nix run .#apply-nix-settings` | `/etc/nix/nix.custom.conf`に Nix daemon 設定を同期 |
| `nix run .#apply-secrets` | sops secrets の復号・配置(鍵が無ければスキップ) |
| `nix run .#apply-winget` | Windows側パッケージの適用(WSLのみ。事前に`nix run .#switch`で`dev.winget`の配置が必要) |
| `nix run .#pptx -- <cmd>` | PPTX 変換ツールチェーン(markitdown / python-pptx / LibreOffice)入り環境でコマンド実行 |
| `nix run .#markdownlint` | リポジトリ管理の技術文書モードで markdownlint 実行 |
| `nix run .#textlint` | リポジトリ管理の日本語向け技術文書モードで textlint 実行 |

`--jobs`は、GitHub Releasesにあるassetのprefetch数だけを制御する。値は1〜4で、既定値は1のため、並列化する場合は明示的に指定する。同時に実行するasset prefetchは`--jobs`の指定数までで、retryはassetごとに行う。したがって、1 targetあたりのasset downloadの最大試行数は、asset数×`--retry`の指定回数になる。上流metadataの取得、source hashのprefetch、flake inputの更新、依存hashの計算、package buildは逐次実行する。

`--check`は、更新候補の取得、hash計算、package build、検証までを通常の更新と同じtransactionで実行し、成功後に管理fileを元の内容・mode・存在状態へ戻す。network access、download cache、Nix storeへのbuild結果は発生するため、副作用のないdry-runではない。同じversionも含めて配布物とbuild contractを再検証する場合は、`--force --check <target>`を使う。

`shellfirm`の`Cargo.lock`には、上流releaseとは別に、このリポジトリで適用するsecurity updateを含める。同じversionに対する`--force`では現在のlockfileを保持し、version更新時に新しい上流lockfileへ切り替える。

## 構成

```text
flake.nix          # inputs / ホスト定義 / 出力の組み立て
nix/
├── lib/           # 構成ビルダーと共有設定生成器
├── modules/       # home (共通) / darwin / linux / wsl (+ windows companion)
├── hosts/         # ホストごとのモジュール束ね
├── packages/      # pkgs.dotfilesPackages に置く実装と明示的な登録
├── overlays/      # 登録の適用、外部 input の橋渡し、意図的な上書き
├── pins/          # 配布物の version や hash (update-pins が更新)
└── apps/          # pptx / markdownlint / textlint / update-pins
agents/skills/     # ローカル agent skills
pi/                # Pi 拡張 (extensions/)
claude/            # Claude Code 設定
secrets/           # sops + GPG 暗号化 secrets (運用は secrets/README.md)
```

sshは`~/.ssh/config`(Include 1行)と`~/.ssh/config.d/`の断片をNixが管理し、秘匿ホストはsopsで暗号化して`apply-secrets`で復号する。
デバイス固有の設定は`~/.ssh/config.d/90-local.conf`のように手で置く。

## ライセンス

既定はCC0-1.0([LICENSE](LICENSE))。由来が異なるファイルはsidecar(`.license`)で明示(REUSE準拠)。
