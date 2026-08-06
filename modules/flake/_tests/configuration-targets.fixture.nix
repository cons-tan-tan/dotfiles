let
  windows = {
    enable = true;
    username = "alice-win";
    homedir = "/mnt/c/Users/alice-win";
  };
  primaryUser = {
    userName = "alice";
    dotfiles.primary = true;
  };
in
{
  inherit primaryUser windows;
  den = {
    hosts = {
      aarch64-darwin.laptop = {
        dotfiles = {
          environment = "darwin";
          source = "/Users/alice/source";
        };
        intoAttr = [
          "darwinConfigurations"
          "workstation"
        ];
        users.alice = primaryUser;
      };
      x86_64-linux.nixos-entry = {
        dotfiles = {
          environment = "wsl";
          source = "/nix/store/wsl-source";
          inherit windows;
        };
        intoAttr = [
          "nixosConfigurations"
          "wsl-primary"
        ];
        users.alice = primaryUser;
      };
    };
    homes.x86_64-linux = {
      linux-entry = {
        userName = "alice";
        dotfiles = {
          environment = "linux";
          source = "/home/alice/source";
        };
        intoAttr = [
          "homeConfigurations"
          "alice@linux"
        ];
      };
      wsl-entry = {
        userName = "alice";
        dotfiles = {
          environment = "wsl";
          source = "/home/alice/source";
          inherit windows;
        };
        intoAttr = [
          "homeConfigurations"
          "alice@wsl"
        ];
      };
    };
  };
}
