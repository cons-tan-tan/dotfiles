# dotfiles

Nix flakeでmacOS、WSL、Linuxの開発環境を宣言的に管理する。WSLではWindows側のcompanion設定も扱う。

## セットアップ

前提はNix（flakes有効）とこのリポジトリのcloneだけ。GPG鍵やsecretsが無くてもswitchは完結する。
NixOS以外では、初回にOS側のNix daemon設定を同期する。
`apply-nix-settings`は`/etc/nix/nix.conf`が同じディレクトリの`nix.custom.conf`をincludeしている環境向け。
installerが管理する設定との衝突を避けるため、対応していない構成は自動変更せず停止する。その場合はincludeを追加するか、daemon設定を別管理するか、この手順をskipして`switch`に進む。skipしても構成は適用できるが、このflake向けのbinary cacheとtrusted-user設定はdaemonへ反映されない。

```sh
git clone https://github.com/cons-tan-tan/dotfiles.git ~/ghq/github.com/cons-tan-tan/dotfiles
cd ~/ghq/github.com/cons-tan-tan/dotfiles
nix run .#apply-nix-settings
```

`apply-nix-settings`の案内に従ってNix daemonを再起動してから、構成を適用する。

```sh
nix run .#switch
```

secretsを使う端末の追加手順は[secrets/README.md](secrets/README.md)を参照する。

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

## 日常操作

| コマンド | 内容 |
| --- | --- |
| `nix run .#switch` | ホスト構成をビルドして適用 |
| `nix run .#build` | ホスト構成を適用せずビルドのみ |
| `nix run .#update` | flake.lock を更新 |
| `nix run .#update-pins -- --list` | packageごとのupstream同期対象を表示 |
| `nix run .#write-flake` | input moduleから`flake.nix`を再生成 |
| `nix run .#apply-winget` | `switch`後にWindows側のpackage構成を適用（WSLのみ） |

そのほかの公開appは`nix flake show`で確認する。

`update-pins`は各packageの`passthru.updateScript`を実行する。対象を省略すると全件を更新し、`nix run .#update-pins -- hcom`のように名前を渡すと1件だけ更新する。更新にはcleanなworktreeが必要で、使い捨てのcloneで全対象が成功してから差分を反映する。`--check`を付けると差分を反映せず、更新が必要な場合に失敗する。通常のpackage更新は`nix-update`へ委譲し、複数assetやflake inputを同時に扱う更新だけを各featureのscriptで補う。GitHub releaseを参照する対象には、`gh auth login`または`GH_TOKEN`による認証が必要となる。旧updaterの`--force`、`--jobs`、`--retry`はpackage側へ更新処理を移したため廃止した。

`flake-file.inputs`を定義するmoduleを直接変更した場合は、`nix run .#write-flake`で`flake.nix`を再生成する。inputを所有する`updateScript`は、`flake.nix`と`flake.lock`も更新する。

## ライセンス

既定はCC0-1.0([LICENSE](LICENSE))。由来が異なるファイルはsidecar(`.license`)で明示(REUSE準拠)。
