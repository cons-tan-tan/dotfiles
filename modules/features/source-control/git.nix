{ ... }:
{
  features.source-control-git = {
    name = "feature/source-control/git";
    homeManager =
      { lib, pkgs, ... }:
      let
        gitLib = import ./_lib/git.nix { inherit lib pkgs; };
      in
      {
        programs.git = {
          enable = true;
          signing = {
            format = "openpgp";
            key = gitLib.signingKey;
            signByDefault = true;
          };
          settings = gitLib.mkSettings { };
          inherit (gitLib) ignores;
        };
      };
  };
}
