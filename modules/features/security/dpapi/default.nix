{ ... }:
{
  features.security-dpapi = {
    name = "feature/security/dpapi";
    nixos =
      { pkgs, ... }:
      {
        # The feature owns the reusable WSL-to-Windows DPAPI capability. Which
        # environments receive it remains a decision of their calling aspect.
        environment.systemPackages = [ pkgs.dotfilesPackages.wsl-dpapi ];
      };
  };
}
