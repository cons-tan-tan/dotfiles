{
  inputs,
  username,
  homedir,
}:
{
  system,
  hostFile,
}:
inputs.nix-darwin.lib.darwinSystem {
  inherit system;
  specialArgs = { inherit username homedir; };
  modules = [
    { nixpkgs.pkgs = (import ./mk-pkgs.nix { inherit inputs; }) system; }
    ../modules/darwin/system.nix

    inputs.home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = { inherit inputs; };
      home-manager.users.${username}.imports = import ./mk-home-modules.nix {
        inherit username homedir hostFile;
        hostKind = "darwin";
      };
    }
  ];
}
