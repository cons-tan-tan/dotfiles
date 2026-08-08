{
  features.development-python = {
    name = "feature/development/python";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [
          pkgs.uv
          pkgs.ruff
          pkgs.ty
          pkgs.basedpyright
        ];
      };
  };
}
