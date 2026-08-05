{ ... }:
{
  features.windows-powershell = {
    name = "feature/windows/powershell";
    windows.dotfiles.windows.deployments.powershell = {
      directories = [ "Documents/PowerShell" ];
      files = [
        {
          source = toString ./_data/Microsoft.PowerShell_profile.ps1;
          destination = "Documents/PowerShell/Microsoft.PowerShell_profile.ps1";
        }
      ];
    };
  };
}
