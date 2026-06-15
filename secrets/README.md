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

## SSH config secret

`ssh-private.yaml` は構造を YAML として残し、sops で値だけ暗号化する。
`*_unencrypted` の値は平文のまま残るため、Host パターンのように構造として
見たいものだけに使う。

```yaml
hosts:
  - host_unencrypted: example
    options:
      HostName: 192.0.2.10
      User: alice
      Port: 22
  - patterns_unencrypted:
      - internal
      - internal.local
    options:
      HostName: internal.example.com
      User: alice
```

`nix run .#apply-secrets` はこれを `~/.ssh/config.d/50-private.conf` の
OpenSSH config 断片へレンダリングして配置する。

## ファイル

| ファイル | 復号先 | 内容 |
| --- | --- | --- |
| `ssh-private.yaml` | `~/.ssh/config.d/50-private.conf` | 秘匿ホスト(実 IP・アカウント名等)の ssh config 断片 |
