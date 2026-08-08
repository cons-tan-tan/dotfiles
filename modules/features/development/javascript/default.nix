{
  features.development-javascript = {
    name = "feature/development/javascript";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [
          pkgs.ni
          pkgs.pnpm
        ];
      };
  };
}
