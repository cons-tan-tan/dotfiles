{ pkgs, lib, ... }:
let
  profiles = {
    "profile nagase" = {
      region = "ap-northeast-1";
      output = "json";
      # login_session を認識しないツール (Terraform S3 backend, Starship等) 向けのワークアラウンド
      credential_process = "aws configure export-credentials --profile nagase --format process";
    };
  };

  # aws login は credential_process があるプロファイルへの実行を拒否するため除外
  loginProfiles = lib.mapAttrs (_: v: removeAttrs v [ "credential_process" ]) profiles;

  baselineFile = pkgs.writeText "aws-config-baseline" (lib.generators.toINI { } profiles);
  loginConfigFile = pkgs.writeText "aws-config-login" (lib.generators.toINI { } loginProfiles);

  # aws login → login_session を本来の config にマージするラッパー
  awsLoginWrapper = pkgs.writeShellScriptBin "aws-login" ''
    config_file="''${AWS_CONFIG_FILE:-$HOME/.aws/config}"

    # credential_process なしの一時 config を作成
    login_config=$(mktemp)
    cp ${loginConfigFile} "$login_config"
    chmod 600 "$login_config"

    # 一時 config に向けて aws login を実行（login_session が一時 config に書き込まれる）
    AWS_CONFIG_FILE="$login_config" ${pkgs.awscli2}/bin/aws login "$@"

    # login_session を本来の config にマージし、一時ファイルを削除
    ${pkgs.crudini}/bin/crudini --merge "$config_file" < "$login_config"
    rm -f "$login_config"
  '';
in
{
  home.packages = with pkgs; [
    awscli2
    awsLoginWrapper
  ];

  # aws login が ~/.aws/config に直接書き込むため、mutable なファイルとして管理する。
  # baseline で上書きし、login_session のみ復元することで宣言外の設定を除外する。
  home.activation.awsConfigMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    config_file="$HOME/.aws/config"
    crudini="${pkgs.crudini}/bin/crudini"

    # 各プロファイルの login_session を退避
    ${lib.concatMapStringsSep "\n    " (name:
      let varName = "login_session_${lib.replaceStrings [ "profile " "-" ] [ "" "_" ] name}";
      in ''${varName}=$($crudini --get "$config_file" "${name}" login_session 2>/dev/null || true)''
    ) (lib.attrNames profiles)}

    # baseline で上書き
    cp ${baselineFile} "$config_file"
    chmod 600 "$config_file"

    # login_session を復元
    ${lib.concatMapStringsSep "\n    " (name:
      let varName = "login_session_${lib.replaceStrings [ "profile " "-" ] [ "" "_" ] name}";
      in ''
        if [ -n "''${${varName}}" ]; then
          $crudini --set "$config_file" "${name}" login_session "''${${varName}}"
        fi''
    ) (lib.attrNames profiles)}
  '';
}
