{
  inputs,
  username,
  homedir,
  windowsUsername,
  windowsHomedir,
  pkgsFor,
}:
{ system }:
inputs.nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = { inherit username; };
  modules = [
    { nixpkgs.pkgs = pkgsFor.${system}; }
    inputs.nixos-wsl.nixosModules.default
    ../modules/nixos-wsl
    {
      # /etc/nixosへこのflake snapshotを同梱し、clone前でも同じsystemを
      # recovery/buildできるようにする。通常の編集はcanonical cloneで行う。
      wsl.tarball.configPath = inputs.self.outPath;
      nix.channel.enable = false;
    }

    inputs.home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "hm-backup";
      home-manager.extraSpecialArgs = { inherit inputs; };
      home-manager.users.${username}.imports = import ./mk-home-modules.nix {
        inherit
          username
          homedir
          windowsUsername
          windowsHomedir
          ;
        hostKind = "wsl";
        hostFile = ../hosts/wsl.nix;

        # 独自tarballの初回起動ではclone先がまだ存在しないため、activationと
        # out-of-store symlinkの参照元をtarballに含まれるflake sourceへ向ける。
        dotfilesDir = inputs.self.outPath;
      };
    }
  ];
}
