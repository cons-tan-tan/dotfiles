{ features, ... }:
{
  features.shell-direnv = {
    name = "feature/shell/direnv";
    homeManager.programs.direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };
  };

  features.shell-direnv-nixbuild-wsl = {
    name = "feature/shell/direnv/nixbuild-wsl";
    includes = [
      features.security-gpg-wsl
      features.shell-direnv
    ];
    nixos =
      { config, ... }:
      let
        username = config.wsl.defaultUser;
        uid = config.users.users.${username}.uid;
      in
      {
        # Distributed builds run as root, so explicitly expose the existing
        # user GPG agent instead of provisioning a separate private key.
        systemd.services.nix-daemon.environment.SSH_AUTH_SOCK =
          "/run/user/${toString uid}/gnupg/S.gpg-agent.ssh";
      };
    homeManager =
      {
        lib,
        pkgs,
        ...
      }:
      let
        nixbuild = {
          host = "ssh://eu.nixbuild.net";
          maxJobs = 100;
          speedFactor = 1;
          supportedFeatures = [
            "big-parallel"
            "benchmark"
          ];

          # Published by nixbuild.net for pinning eu.nixbuild.net without
          # depending on the nix-daemon user's known_hosts file.
          publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVBJUUNaYzU0cG9KOHZxYXdkOFRyYU5yeVFlSm52SDFlTHBJRGdiaXF5bU0K";
        };
        nixbuildDirenvrc = ''
          ${builtins.readFile ./_data/nixbuild-direnvrc.sh}

          use_nixbuild_for_ghq_owner \
            ${lib.escapeShellArg "cons-tan-tan"} \
            ${lib.escapeShellArg pkgs.stdenv.hostPlatform.system} \
            ${lib.escapeShellArg nixbuild.host} \
            ${lib.escapeShellArg (toString nixbuild.maxJobs)} \
            ${lib.escapeShellArg (toString nixbuild.speedFactor)} \
            ${lib.escapeShellArg (lib.concatStringsSep "," nixbuild.supportedFeatures)} \
            ${lib.escapeShellArg nixbuild.publicHostKey}
        '';
      in
      {
        programs.direnv.stdlib = nixbuildDirenvrc;
      };
  };
}
