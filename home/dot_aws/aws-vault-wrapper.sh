#!/usr/bin/bash

PROFILE="nagase"
SESSION_DURATION="12h"

# セッションの状態を確認する関数
check_session() {
    local sessions
    sessions=$(aws-vault list --sessions 2>/dev/null)

    # セッションが存在しない場合はfalse
    [ -z "$sessions" ] && return 1

    # マイナスの時間（期限切れセッション）が含まれている場合はfalse
    echo "$sessions" | grep -q ":-" && return 1

    # 上記以外の場合は有効なセッションが存在する
    return 0
}

# メイン処理
if check_session; then
    aws-vault export $PROFILE --format=json --duration=$SESSION_DURATION
else
    mfa_token=$(op item get AWS --otp)
    aws-vault export $PROFILE --format=json --duration=$SESSION_DURATION --mfa-token=$mfa_token
fi
