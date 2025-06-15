#!/usr/bin/bash

PROFILE="nagase"
SESSION_DURATION="12h"
OP_AWS_ITEM_ID="tb4wzijx2dxtk2g465gunpe7pe"

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
    aws-vault exec $PROFILE --json --prompt=terminal --duration=$SESSION_DURATION
else
    mfa_token=$(op item get $OP_AWS_ITEM_ID --otp)
    aws-vault exec $PROFILE --json --prompt=terminal --duration=$SESSION_DURATION --mfa-token=$mfa_token
fi
