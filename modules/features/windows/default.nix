{ features, ... }:
{
  features.windows-default = {
    name = "feature/windows";
    includes = [
      features.windows-base
      features.windows-powershell
      features.cli-tools-winget
    ];
  };
}
