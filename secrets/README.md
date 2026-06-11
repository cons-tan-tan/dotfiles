# secrets

sops + GPG で暗号化した secrets を置くディレクトリ。平文はコミットしない。

## 役割分担

- **sops**(ここ): リポジトリにコミットする宣言的 secrets(ssh の秘匿ホスト断片など)
- **gopass**: 対話的なパスワード管理(リポジトリ外)

## 使い方

```shell
# 作成・編集(.sops.yaml の GPG recipient で自動暗号化される)
sops edit secrets/ssh-private.conf

# 適用(復号して ~/.ssh/config.d/50-private.conf に配置)
nix run .#apply-secrets
```

GPG 秘密鍵が未導入のデバイスでは `apply-secrets` は警告だけ出してスキップする
(switch は secrets に依存しないので、復号できなくても環境構築は完結する)。

## ファイル

| ファイル | 復号先 | 内容 |
| --- | --- | --- |
| `ssh-private.conf` | `~/.ssh/config.d/50-private.conf` | 秘匿ホスト(実 IP・アカウント名等)の ssh config 断片 |
