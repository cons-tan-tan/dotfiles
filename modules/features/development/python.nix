{
  flake.modules.homeManager.development-python =
    { pkgs, ... }:
    {
      key = "modules/features/development/python.nix#homeManager.development-python";

      home.packages = [
        pkgs.uv
        pkgs.ruff
        pkgs.ty
        pkgs.basedpyright
      ];
    };
}
