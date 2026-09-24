{
  flake.modules.homeManager.windows-powershell = { config, lib, ... }: {
    key = "modules/features/windows/powershell.nix#homeManager.windows-powershell";
    config = lib.mkIf config.dotfiles.platform.windows.enable {
      dotfiles.windows.deployments.powershell = {
        directories = [ "Documents/PowerShell" ];
        files = [
          {
            source = toString ./_data/Microsoft.PowerShell_profile.ps1;
            destination = "Documents/PowerShell/Microsoft.PowerShell_profile.ps1";
          }
        ];
      };
    };
  };
}
