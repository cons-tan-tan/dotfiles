{ pkgs, ... }:
let
  curl-fetch = pkgs.writeShellScriptBin "curl-fetch" ''
    set -euo pipefail

    DENY_SHORT_CHARS="XdFTKQ:"
    ATFILE_ERR="Error: '@file' syntax is not allowed in header values"

    DENY_LONG_FLAGS=(
      --request --request-target
      --data --data-ascii --data-binary --data-raw --data-urlencode
      --form --form-string
      --upload-file
      --json
      --config
      --quote
      --next
      --post301 --post302 --post303
    )

    # -H/--header/--proxy-header の次の引数を検査するためのフラグ
    check_header_value=false

    for arg in "$@"; do
      if $check_header_value; then
        check_header_value=false
        if [[ "$arg" == @* ]]; then
          echo "$ATFILE_ERR" >&2
          exit 1
        fi
        continue
      fi

      if [[ "$arg" == "--" ]]; then
        echo "Error: '--' is not allowed" >&2
        exit 1
      fi

      # 長フラグのチェック（--flag=value 形式も考慮）
      if [[ "$arg" == --* ]]; then
        flag="''${arg%%=*}"
        for denied in "''${DENY_LONG_FLAGS[@]}"; do
          if [[ "$flag" == "$denied" ]]; then
            echo "Error: '$denied' is not allowed" >&2
            exit 1
          fi
        done
        # --header=@file / --proxy-header=@file の検査
        if [[ ("$flag" == "--header" || "$flag" == "--proxy-header") && "$arg" == *=@* ]]; then
          echo "$ATFILE_ERR" >&2
          exit 1
        fi
        if [[ "$arg" == "--header" || "$arg" == "--proxy-header" ]]; then
          check_header_value=true
        fi
        continue
      fi

      # 短フラグのチェック（結合形 -sXPOST 等も検出）
      if [[ "$arg" == -* ]]; then
        chars="''${arg#-}"
        for (( i=0; i<''${#chars}; i++ )); do
          c="''${chars:$i:1}"
          if [[ "$DENY_SHORT_CHARS" == *"$c"* ]]; then
            echo "Error: '-$c' is not allowed" >&2
            exit 1
          fi
          # -H は引数を取るため、残りの文字が値になる
          if [[ "$c" == "H" ]]; then
            rest="''${chars:$((i+1))}"
            if [[ -n "$rest" && "$rest" == @* ]]; then
              echo "$ATFILE_ERR" >&2
              exit 1
            fi
            if [[ -z "$rest" ]]; then
              check_header_value=true
            fi
            break
          fi
        done
      fi
    done

    # -q: .curlrc の自動読み込みを無効化し、設定ファイル経由のフラグ注入を防止
    exec ${pkgs.curl}/bin/curl -q "$@"
  '';
in
{
  home.packages = [
    pkgs.curl
    curl-fetch
  ];
}
