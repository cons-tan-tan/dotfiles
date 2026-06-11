{
  inputs,
  username,
  homedir,
  windowsUsername,
  windowsHomedir,
}:
{
  hostKind,
  system,
  hostFile,
}:
inputs.home-manager.lib.homeManagerConfiguration {
  pkgs = (import ./mk-pkgs.nix { inherit inputs; }) system;
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
