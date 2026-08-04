{ features, ... }:
{
  features.windows-default = {
    name = "feature/windows";
    includes = [
      features.windows-base
      features.windows-powershell
      features.windows-static
      features.windows-winget
    ];
  };
}
