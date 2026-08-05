# secrets

sops + GPGで暗号化したsecretsを置くディレクトリ。平文はコミットしない。

## 役割分担

- リポジトリにコミットする宣言的secrets(sshの秘匿ホスト断片など)には**sops**を使う。
- リポジトリ外で対話的に管理するパスワードには**gopass**を使う。

## 使い方

```shell
# 作成・編集(.sops.yaml の GPG recipient で自動暗号化される)
sops edit secrets/<name>

# 書き込み先の一覧確認のみ(実環境を触らない)
nix run .#apply-secrets -- --dry-run

# 適用(復号して配置先に書き込む)
nix run .#apply-secrets
```

GPG秘密鍵が未導入のデバイスでは`apply-secrets`は警告だけ出してスキップする
(switchはsecretsに依存しないので、復号できなくても環境構築は完結する)。
ただしmanifestのmissing sourceやunsafe dstはリポジトリ誤りとして失敗する。

## 新しい secret の追加手順

1. `sops edit secrets/<name>`で作成(`.sops.yaml`により自動暗号化される)
2. `modules/features/security/secrets/_data/manifest.nix`にエントリを追加:

   ```nix
   { src = "secrets/<name>"; dst = "<home-relative-path>"; mode = "600"; dirMode = "700"; }
   ```

3. `nix run .#apply-secrets -- --dry-run`でdstを確認してから実適用

## SSH config secret

`ssh-private.yaml`は構造をYAMLとして残し、sopsで値だけ暗号化する。
`*_unencrypted`の値は平文のまま残るため、Hostパターンのように構造として
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

`nix run .#apply-secrets`はこれを`~/.ssh/config.d/50-private.conf`の
OpenSSH config断片へレンダリングして配置する。

## ファイル

| ファイル | 復号先 | 内容 |
| --- | --- | --- |
| `ssh-private.yaml` | `~/.ssh/config.d/50-private.conf` | 秘匿ホスト(実 IP・アカウント名等)の ssh config 断片 |
