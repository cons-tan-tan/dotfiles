{
  pkgs,
  username,
}:
let
  appSet = import ../../../apps/_interface/app-set.nix { lib = pkgs.lib; };
  settings = import ./custom-settings.nix {
    inherit (pkgs) lib;
    inherit username;
  };
  settingsFile = pkgs.writeText "dotfiles-nix-custom.conf" settings.text;
  core = pkgs.callPackage ../_packages/apply-nix-settings { };
  script = pkgs.writeShellApplication {
    name = "apply-nix-settings";
    text = ''
      export APPLY_NIX_SETTINGS_SNIPPET=${settingsFile}
      exec ${pkgs.lib.getExe core} "$@"
    '';
  };
in
appSet.mkAppSet {
  entries.apply-nix-settings = {
    description = "Sync root-level Nix daemon settings into /etc/nix/nix.custom.conf";
    inherit script;
  };
}
