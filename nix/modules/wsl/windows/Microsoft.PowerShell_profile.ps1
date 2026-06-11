# PowerShell profile (managed by Nix - do not edit directly)
# Source: nix/modules/wsl/windows/Microsoft.PowerShell_profile.ps1

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}
