# ~/.ssh/config 本体は Include 1 行のみの定型ファイルとして Nix 管理し、
# 実際の設定はすべて ~/.ssh/config.d/ 配下の断片に置く:
#
#   10-common.conf  - 全環境共通 (このモジュールが配置)
#   50-private.conf - 秘匿ホスト (sops 暗号化の secrets/ssh-private.yaml を
#                     `nix run .#apply-secrets` で復号・レンダリングして配置)
#   90-local.conf 等 - デバイス固有の一時設定が必要なら手で置く (Nix 管理外)
#
# OpenSSH の Include はマッチしない glob を黙って無視するため、秘匿断片が
# 未復号でも ssh は壊れない (GPG 鍵導入前の新デバイスでも switch だけで成立)。
#
# 秘匿断片を home.file にしないのは、Nix store が全ユーザー読み取り可能で
# 秘匿情報を置けないため。runtime 復号 (apply-secrets) が正しい置き場になる。
#
# 既存の手書き ~/.ssh/config があるデバイスでは HM が黙って上書きせず
# .hm-backup に退避してログに明示する (darwin: backupFileExtension /
# standalone: switch app の -b hm-backup)。
{ ... }:
{
  home.file.".ssh/config".text = ''
    Include ~/.ssh/config.d/*.conf
  '';

  # 全環境共通の断片のみ置く。環境固有の差分はこのファイルに足さず、
  # 50-private.conf (sops) か手置きの断片に残す。
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
