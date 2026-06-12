{
  inputs,
  username,
  homedir,
  windowsUsername,
  windowsHomedir,
  pkgsFor,
}:
{
  hostKind,
  system,
  hostFile,
}:
inputs.home-manager.lib.homeManagerConfiguration {
  pkgs = pkgsFor.${system};
  extraSpecialArgs = { inherit inputs; };
  modules = import ./mk-home-modules.nix {
    inherit
      username
      homedir
      hostKind
      hostFile
      windowsUsername
      windowsHomedir
      ;
  };
}
