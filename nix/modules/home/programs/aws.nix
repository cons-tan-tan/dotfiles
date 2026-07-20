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

  awsLoginWrapper = pkgs.dotfilesPackages.aws.mkLoginPackage {
    inherit loginConfigFile;
  };
in
{
  home.packages = with pkgs; [
    awscli2
    awsLoginWrapper
  ];

  # aws login が ~/.aws/config に直接書き込むため、mutable なファイルとして管理する。
  # baseline で上書きし、login_session のみ復元することで宣言外の設定を除外する。
  # 候補ファイルを組み立ててから最後にアトミックに mv する — 途中で失敗しても
  # 既存の login_session を失わないため。書き込み系は run 経由 (dry-run 安全)。
  home.activation.awsConfigMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    (
      set -e
      config_file="$HOME/.aws/config"
      crudini="${pkgs.crudini}/bin/crudini"

      candidate=$(${pkgs.coreutils}/bin/mktemp)
      trap '${pkgs.coreutils}/bin/rm -f "$candidate"' EXIT
      ${pkgs.coreutils}/bin/cp ${baselineFile} "$candidate"
      ${pkgs.coreutils}/bin/chmod 600 "$candidate"

      if [ -f "$config_file" ]; then
        ${lib.concatMapStringsSep "\n        " (name: ''
          session=$($crudini --get "$config_file" ${lib.escapeShellArg name} login_session 2>/dev/null || true)
          if [ -n "$session" ]; then
            $crudini --set "$candidate" ${lib.escapeShellArg name} login_session "$session"
          fi'') (lib.attrNames profiles)}
      fi

      run mkdir -p "$HOME/.aws"
      run ${pkgs.coreutils}/bin/mv -f "$candidate" "$config_file"
    )
  '';
}
