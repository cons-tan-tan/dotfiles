{ features, ... }:
{
  features.trash = {
    name = "feature/trash";
    homeManager = import ./_lib/common.nix;
  };

  features.trash-systemd = {
    name = "feature/trash/systemd";
    includes = [ features.trash ];
    homeManager = import ./_lib/systemd.nix;
  };

  features.trash-darwin = {
    name = "feature/trash/darwin";
    includes = [ features.trash ];
    homeManager = import ./_lib/darwin.nix;
  };
}
