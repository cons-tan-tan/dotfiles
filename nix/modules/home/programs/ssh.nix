# ssh 設定の段階的 Nix 管理 (詳細は README の「ssh / secrets」を参照)。
#
# 既存の ~/.ssh/config は Nix 管理外のまま一切触らない: Mac と WSL で内容が
# 乖離しており、どちらかの内容で上書きすると壊れるため。Nix が管理するのは
# ~/.ssh/config.d/ 配下の断片だけで、利用者が既存 config の先頭に
#
#   Include ~/.ssh/config.d/*.conf
#
# を 1 行手動で追加して有効化する。OpenSSH の Include はマッチしない glob を
# 黙って無視するため、断片が未配置でも ssh は壊れない (新デバイスでもこの
# モジュールが入るだけで害はない)。
#
# 秘匿ホスト (実 IP・アカウント名等) は secrets/ssh-private.conf (sops 暗号化)
# を `nix run .#secrets-apply` で ~/.ssh/config.d/50-private.conf に復号して
# 配置する。未復号でも Include glob のおかげで自然にフォールバックする。
{ ... }:
{
  # 全環境共通の断片のみ置く。環境固有の差分はこのファイルに足さず、
  # 50-private.conf (sops) か各環境の手書き config に残す。
  home.file.".ssh/config.d/10-common.conf".text = ''
    # Managed by Nix (nix/modules/home/programs/ssh.nix) - do not edit directly

    Host github.com
        HostName github.com
        User git

    Host *
        ServerAliveInterval 60
        TCPKeepAlive yes
  '';
}
