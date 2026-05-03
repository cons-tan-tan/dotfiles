{
  pkgs,
  lib,
  hostKind,
  windowsHomedir,
  ...
}:
let
  hk = import ../../../lib/host-kind.nix { inherit hostKind; };

  profileContent = ''
    # PowerShell profile (managed by Nix - do not edit directly)
    # Source: nix/modules/wsl/windows/powershell.nix

    if (Get-Command starship -ErrorAction SilentlyContinue) {
        Invoke-Expression (& starship init powershell)
    }

    if (Get-Command zoxide -ErrorAction SilentlyContinue) {
        Invoke-Expression (& { (zoxide init powershell | Out-String) })
    }
  '';

  profileFile = pkgs.writeText "Microsoft.PowerShell_profile.ps1" profileContent;
in
{
  home.activation = lib.mkIf hk.hasWindowsCompanion {
    deployPowerShellProfile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      WIN_PWSH_PROFILE_DIR=${windowsHomedir}/Documents/PowerShell
      run mkdir -p "$WIN_PWSH_PROFILE_DIR"
      run install -m644 ${profileFile} \
        "$WIN_PWSH_PROFILE_DIR/Microsoft.PowerShell_profile.ps1"
    '';
  };
}
