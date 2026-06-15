# secrets

sops + GPG で暗号化した secrets を置くディレクトリ。平文はコミットしない。

## 役割分担

- **sops**(ここ): リポジトリにコミットする宣言的 secrets(ssh の秘匿ホスト断片など)
- **gopass**: 対話的なパスワード管理(リポジトリ外)

## 使い方

```shell
# 作成・編集(.sops.yaml の GPG recipient で自動暗号化される)
sops edit secrets/<name>

# 書き込み先の一覧確認のみ(実環境を触らない)
nix run .#apply-secrets -- --dry-run

# 適用(復号して配置先に書き込む)
nix run .#apply-secrets
```

GPG 秘密鍵が未導入のデバイスでは `apply-secrets` は警告だけ出してスキップする
(switch は secrets に依存しないので、復号できなくても環境構築は完結する)。
ただし manifest の missing source や unsafe dst はリポジトリ誤りとして失敗する。

## 新しい secret の追加手順

1. `sops edit secrets/<name>` で作成(`.sops.yaml` により自動暗号化される)
2. `nix/lib/mk-apps.nix` の `secretsManifest` にエントリを追加:
   ```nix
   { src = "secrets/<name>"; dst = "<home-relative-path>"; mode = "600"; dirMode = "700"; }
   ```
3. `nix run .#apply-secrets -- --dry-run` で dst を確認してから実適用

## ファイル

| ファイル | 復号先 | 内容 |
| --- | --- | --- |
| `ssh-private.conf` | `~/.ssh/config.d/50-private.conf` | 秘匿ホスト(実 IP・アカウント名等)の ssh config 断片 |
