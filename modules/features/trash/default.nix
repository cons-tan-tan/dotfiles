{ features, ... }:
{
  features.trash = {
    name = "feature/trash";
  };

  features.trash-systemd = {
    name = "feature/trash/systemd";
    includes = [ features.trash ];
  };

  features.trash-darwin = {
    name = "feature/trash/darwin";
    includes = [ features.trash ];
  };
}
