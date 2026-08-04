# PowerShell profile (managed by Nix - do not edit directly)
# Source: modules/features/windows/_lib/Microsoft.PowerShell_profile.ps1

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}
