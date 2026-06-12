{
  inputs,
  username,
  homedir,
  pkgsFor,
}:
{
  system,
  hostFile,
}:
inputs.nix-darwin.lib.darwinSystem {
  inherit system;
  specialArgs = { inherit username homedir; };
  modules = [
    { nixpkgs.pkgs = pkgsFor.${system}; }
    ../modules/darwin/system.nix

    inputs.home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      # 非管理ファイルと衝突した場合はエラーで止まらずバックアップを残して
      # 置換する (force = true 原則禁止ポリシーとセットの安全網)
      home-manager.backupFileExtension = "hm-backup";
      home-manager.extraSpecialArgs = { inherit inputs; };
      home-manager.users.${username}.imports = import ./mk-home-modules.nix {
        inherit username homedir hostFile;
        hostKind = "darwin";
      };
    }
  ];
}
