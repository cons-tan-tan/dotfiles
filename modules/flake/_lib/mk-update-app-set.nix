{ pkgs }:
let
  appSet = import ../../features/apps/_interface/app-set.nix { lib = pkgs.lib; };
  script = pkgs.writeShellApplication {
    name = "flake-update";
    text = ''
      echo "Updating flake.lock..."
      nix flake update
      echo "Done! Run 'nix run .#switch' to apply changes."
    '';
  };
in
appSet.mkAppSet {
  entries.update = {
    description = "Update flake.lock to the latest input revisions";
    inherit script;
  };
}
