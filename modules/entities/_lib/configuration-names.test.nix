{ }:
let
  configNames = import ./configuration-names.nix { username = "alice"; };
in
{
  testHomeConfigurationNames = {
    expr = [
      (configNames.forHost {
        hostKind = "linux";
        system = "x86_64-linux";
      })
      (configNames.forHost {
        hostKind = "wsl";
        system = "aarch64-linux";
      })
    ];
    expected = [
      "alice@linux-x86_64"
      "alice@wsl-aarch64"
    ];
  };

  testNixosWslConfigurationNames = {
    expr = [
      (configNames.forNixosWsl { system = "x86_64-linux"; })
      (configNames.forNixosWsl { system = "aarch64-linux"; })
    ];
    expected = [
      "wsl"
      "wsl-aarch64"
    ];
  };
}
