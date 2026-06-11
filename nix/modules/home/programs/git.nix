{
  pkgs,
  lib,
  ...
}:
let
  gitLib = import ../../../lib/settings/git.nix { inherit lib pkgs; };
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
}
