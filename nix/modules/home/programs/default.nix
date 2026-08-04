{ inputs, ... }:
let
  withInputs =
    path:
    {
      config,
      lib,
      pkgs,
      ...
    }:
    import path {
      inherit
        config
        inputs
        lib
        pkgs
        ;
    };
in
{
  imports = [
    ./aws.nix
    (withInputs ./claude.nix)
    ./codex.nix
    ./curl.nix
    ./direnv.nix
    ./gcloud.nix
    ./gh.nix
    ./ghq-sync.nix
    ./git.nix
    ./git-wt.nix
    ./gpg.nix
    ./herdr.nix
    (withInputs ./hunk.nix)
    ./nh.nix
    ./opencode.nix
    ./pi.nix
    ./ssh.nix
    ./starship.nix
    ./zoxide.nix
    ./zsh.nix
  ];
}
