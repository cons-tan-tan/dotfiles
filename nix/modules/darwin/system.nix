{
  pkgs,
  lib,
  username,
  homedir,
  ...
}:
{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Disable nix-darwin's Nix management (using Determinate Nix)
  # Note: Nix settings are managed via /etc/nix/nix.custom.conf instead
  # This file should be manually configured with trusted-users and substituters
  nix.enable = false;

  # Set system state version
  system.stateVersion = 5;

  # Set primary user
  system.primaryUser = username;

  # Define user
  users.users.${username} = {
    home = homedir;
  };

  # Enable Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # macOS system defaults (uncomment as needed)
  # system.defaults = {
  #   # Dock settings
  #   dock = {
  #     autohide = true;
  #     tilesize = 45;
  #     show-recents = false;
  #     orientation = "bottom";
  #   };
  #
  #   # Finder settings
  #   finder = {
  #     AppleShowAllExtensions = true;
  #     AppleShowAllFiles = true;
  #     ShowPathbar = true;
  #     ShowStatusBar = true;
  #     FXEnableExtensionChangeWarning = false;
  #     FXPreferredViewStyle = "Nlsv";
  #   };
  #
  #   # Global macOS settings
  #   NSGlobalDomain = {
  #     AppleInterfaceStyle = "Dark";
  #     AppleShowAllExtensions = true;
  #     KeyRepeat = 2;
  #     InitialKeyRepeat = 25;
  #     NSAutomaticCapitalizationEnabled = false;
  #     NSAutomaticDashSubstitutionEnabled = false;
  #     NSAutomaticPeriodSubstitutionEnabled = false;
  #     NSAutomaticQuoteSubstitutionEnabled = false;
  #     NSAutomaticSpellingCorrectionEnabled = false;
  #   };
  #
  #   # Screenshot settings
  #   screencapture = {
  #     location = "~/Pictures/Screenshots";
  #     type = "png";
  #   };
  # };

  # Homebrew configuration (uncomment to enable)
  # homebrew = {
  #   enable = true;
  #   onActivation.cleanup = "uninstall";
  #   brews = [ ];
  #   casks = [ ];
  #   masApps = { };
  # };
}
