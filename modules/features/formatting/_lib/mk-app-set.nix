{
  formatter,
  pkgs,
}:
let
  appSet = import ../../apps/_interface/app-set.nix { lib = pkgs.lib; };
  script = pkgs.writeShellApplication {
    name = "treefmt-wrapper";
    text = ''
      exec ${formatter}/bin/treefmt "$@"
    '';
  };
in
appSet.mkAppSet {
  entries.fmt = {
    description = "Format the repository with treefmt";
    inherit script;
  };
}
