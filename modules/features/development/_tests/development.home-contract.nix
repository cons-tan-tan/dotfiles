{ }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      countPackage =
        package: builtins.length (builtins.filter (candidate: candidate == package) config.home.packages);
    in
    {
      basedpyright = countPackage pkgs.basedpyright;
      go = countPackage pkgs.go;
      mozukuLsp = countPackage pkgs.mozuku-lsp;
      ni = countPackage pkgs.ni;
      nixd = countPackage pkgs.nixd;
      pnpm = countPackage pkgs.pnpm;
      ruff = countPackage pkgs.ruff;
      rustup = countPackage pkgs.rustup;
      ty = countPackage pkgs.ty;
      uv = countPackage pkgs.uv;
      watchexec = countPackage pkgs.watchexec;
    };
  expected = _: {
    basedpyright = 1;
    go = 1;
    mozukuLsp = 1;
    ni = 1;
    nixd = 1;
    pnpm = 1;
    ruff = 1;
    rustup = 1;
    ty = 1;
    uv = 1;
    watchexec = 1;
  };
}
