{ pkgs, lib, ... }:
let
  # https://gist.github.com/mrgrain/9c3519952d9af811bd7bf50bfcfaa16f
  pinentry-1password = pkgs.writeShellScriptBin "pinentry-1password" ''
    if grep -qi microsoft /proc/version 2>/dev/null; then
      OP_CMD="/mnt/c/Users/zhouc/scoop/shims/op.exe"
    else
      OP_CMD="op"
    fi

    echo "OK"
    while IFS= read -r line; do
      cmd=$(echo "$line" | cut -d' ' -f1)
      case "$cmd" in
        GETPIN)
          PASSPHRASE=$($OP_CMD read "op://Personal/GPG Key/password" --account my.1password.com 2>/dev/null)
          echo "D $PASSPHRASE"
          echo "OK"
          ;;
        BYE)
          echo "OK"
          exit 0
          ;;
        *)
          echo "OK"
          ;;
      esac
    done
  '';
in
{
  programs.gpg = {
    enable = true;
    package = pkgs.gnupg;
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = false;
    pinentry = {
      package = pinentry-1password;
      program = "pinentry-1password";
    };
    defaultCacheTtl = 43200;
    maxCacheTtl = 43200;
  };
}
