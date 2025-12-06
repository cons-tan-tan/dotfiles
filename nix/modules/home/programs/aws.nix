{ pkgs, ... }:
{
  # AWS CLI configuration
  programs.awscli = {
    enable = true;
    settings = {
      "profile nagase" = {
        region = "ap-northeast-1";
        output = "json";
        mfa_serial = "arn:aws:iam::128755073671:mfa/1password";
        credential_process = "aws-vault export nagase --format=json --duration=12h";
        mfa_process = "gopass otp --password aws/otp/nagase";
      };
    };
  };

  # AWS Vault for credential management
  home.packages = with pkgs; [
    aws-vault
  ];
}
