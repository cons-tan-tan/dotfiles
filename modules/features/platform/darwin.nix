{ features, ... }:
{
  features.platform-darwin-system = {
    name = "feature/platform/darwin/system";
    darwin = {
      # Determinate Nix owns the daemon and /etc/nix configuration.
      nix.enable = false;
      system.stateVersion = 5;
    };
  };

  features.platform-darwin-fonts = {
    name = "feature/platform/darwin/fonts";
    darwin = { pkgs, ... }: {
      fonts.packages = with pkgs; [
        hackgen-nf-font
        nerd-fonts.symbols-only
      ];
      security.pam.services.sudo_local.touchIdAuth = true;
    };
  };

  features.platform-homebrew = {
    name = "feature/platform/darwin/homebrew";
    darwin.homebrew = {
      enable = true;
      onActivation = {
        # nix-darwin maps cleanup = "uninstall" to --force-cleanup, while
        # Homebrew Bundle accepts --cleanup for install-time cleanup.
        cleanup = "none";
        extraFlags = [ "--cleanup" ];
      };
      brews = [ ];
      # Simple .app bundles stay in brew-nix below. Installer packages,
      # privileged helpers, and input methods remain real Homebrew casks.
      casks = [
        "azookey"
        "fiji"
        "scroll-reverser"
        "tailscale-app"
      ];
      masApps = { };
    };
  };

  features.platform-darwin-packages = {
    name = "feature/platform/darwin/packages";
    homeManager = { pkgs, ... }: {
      home.packages =
        (with pkgs; [
          dotfilesPackages.codex-app
          raycast
        ])
        ++ (with pkgs.brewCasks; [
          aqua-voice
          zed
        ]);
    };
  };

  features.platform-ghostty = {
    name = "feature/platform/darwin/ghostty";
    homeManager = { pkgs, ... }: {
      programs.ghostty = {
        enable = true;
        package = pkgs.ghostty-bin;
        settings = {
          background-opacity = 0.7;
          font-family = [
            "HackGen Console NF"
            "Symbols Nerd Font Mono"
          ];
        };
      };
    };
  };

  features.platform-sleepctl = {
    name = "feature/platform/sleepctl";
    darwin =
      { config, pkgs, ... }:
      {
        launchd.daemons.sleepctld.serviceConfig = {
          ProgramArguments = [
            "${pkgs.dotfilesPackages.sleepctl}/bin/sleepctld"
            "--allowed-user"
            config.system.primaryUser
          ];
          RunAtLoad = true;
          KeepAlive = true;
          ProcessType = "Background";
          ThrottleInterval = 5;
          StandardOutPath = "/var/log/sleepctld.log";
          StandardErrorPath = "/var/log/sleepctld.err.log";
        };
      };
    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.dotfilesPackages.sleepctl ];
    };
  };

  features.platform-darwin = {
    name = "feature/platform/darwin";
    includes = [
      features.platform-context
      features.platform-darwin-system
      features.platform-darwin-fonts
      features.platform-homebrew
      features.platform-darwin-packages
      features.platform-ghostty
      features.platform-sleepctl
      features.platform-nh
    ];
  };
}
