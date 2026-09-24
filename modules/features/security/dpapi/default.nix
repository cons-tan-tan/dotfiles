{ ... }:
{
  flake.modules.nixos.security-dpapi =
    { pkgs, ... }:
    {
      key = "modules/features/security/dpapi/default.nix#nixos.security-dpapi";

      # The feature owns the reusable WSL-to-Windows DPAPI capability. Which
      # environments receive it remains a decision of their calling profile.
      environment.systemPackages = [ pkgs.dotfilesPackages.wsl-dpapi ];
    };
}
