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
in
{
  home.activation.deployPowerShellProfile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    WIN_PWSH_PROFILE_DIR=${windowsHomedir}/Documents/PowerShell
    run mkdir -p "$WIN_PWSH_PROFILE_DIR"
    run install -m644 ${./Microsoft.PowerShell_profile.ps1} \
      "$WIN_PWSH_PROFILE_DIR/Microsoft.PowerShell_profile.ps1"
  '';
}
