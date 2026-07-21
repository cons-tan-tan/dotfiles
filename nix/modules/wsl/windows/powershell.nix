# Windows companion: PowerShell 7 のプロファイルを書き出す。
#
# NOTE: 配置先は既定の $PROFILE (Documents\PowerShell)。Documents が OneDrive
# リダイレクトされている環境では $PROFILE が OneDrive 配下に移るため、その
# 場合はこのパスを合わせて直すこと (現環境はリダイレクト無し前提)。
{
  config,
  lib,
  ...
}:
let
  windowsHomedir = config.my.windows.homedir;
  deploy = import ./deploy.nix { inherit lib; };
in
{
  home.activation.deployPowerShellProfile = deploy.mkDeployActivation {
    dirs = [ "${windowsHomedir}/Documents/PowerShell" ];
    files = [
      {
        src = ./Microsoft.PowerShell_profile.ps1;
        dst = "${windowsHomedir}/Documents/PowerShell/Microsoft.PowerShell_profile.ps1";
      }
    ];
  };
}
