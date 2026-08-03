{
  inputs,
  pkgsFor,
}:
let
  inherit (inputs) nixpkgs self;
  lib = nixpkgs.lib;
  username = "constantan";

  darwinSystem = "aarch64-darwin";
  darwinHomedir = "/Users/${username}";
  darwinHostname = "${username}";

  linuxHomedir = "/home/${username}";

  # Windows companion (WSL host only)
  windowsUsername = "zhouc";
  windowsHomedir = "/mnt/c/Users/${windowsUsername}";

  ciCheck = import ../../nix/lib/ci-check.nix { inherit lib; };

  mkHost = import ../../nix/lib/mk-host.nix {
    inherit
      inputs
      username
      windowsUsername
      windowsHomedir
      pkgsFor
      ;
    homedir = linuxHomedir;
  };

  mkDarwin = import ../../nix/lib/mk-darwin.nix {
    inherit inputs username pkgsFor;
    homedir = darwinHomedir;
  };

  mkNixosWsl = import ../../nix/lib/mk-nixos-wsl.nix {
    inherit
      inputs
      username
      windowsUsername
      windowsHomedir
      pkgsFor
      ;
    homedir = linuxHomedir;
  };

  linuxHostMatrix = [
    {
      hostKind = "linux";
      system = "x86_64-linux";
      hostFile = ../../nix/hosts/linux.nix;
    }
    {
      hostKind = "linux";
      system = "aarch64-linux";
      hostFile = ../../nix/hosts/linux.nix;
    }
    {
      hostKind = "wsl";
      system = "x86_64-linux";
      hostFile = ../../nix/hosts/wsl.nix;
    }
    {
      hostKind = "wsl";
      system = "aarch64-linux";
      hostFile = ../../nix/hosts/wsl.nix;
    }
  ];

  configNames = import ../../nix/lib/linux-config-name.nix { inherit username; };
  linuxConfigName = configNames.forHost;
  nixosWslConfigName = configNames.forNixosWsl;

  nixosWslMatrix = builtins.filter (entry: entry.hostKind == "wsl") linuxHostMatrix;

  darwinConfigurations = {
    ${darwinHostname} = mkDarwin {
      system = darwinSystem;
      hostFile = ../../nix/hosts/darwin.nix;
    };
  };

  homeConfigurations = lib.listToAttrs (
    map (entry: {
      name = linuxConfigName entry;
      value = mkHost entry;
    }) linuxHostMatrix
  );

  nixosConfigurations = lib.listToAttrs (
    map (entry: {
      name = nixosWslConfigName entry;
      value = mkNixosWsl { inherit (entry) system; };
    }) nixosWslMatrix
  );

in
{
  inherit darwinConfigurations homeConfigurations nixosConfigurations;

  # CI専用gateを別定義するとlocal checksと対象が乖離するため、同じ
  # derivationから導出する。native runnerを用意していないaarch64-linuxは、
  # 実build対象へ見せかけず全system評価だけに留める。
  hydraJobs.ci = ciCheck.mkHestiaJobs {
    x86_64-linux = self.checks.x86_64-linux;
    ${darwinSystem} = self.checks.${darwinSystem};
  };

}
