{ den, ... }:
{
  flake-file.inputs = {
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      inputs.brew-api.follows = "brew-api";
      inputs.nix-darwin.follows = "darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  features.platform-darwin-packages = {
    name = "feature/platform/darwin/packages";
    includes = [
      (den.batteries.unfree [
        "codex-app"
        "raycast"
      ])
    ];
    homeManager = { pkgs, ... }: {
      home.packages =
        (with pkgs; [
          dotfilesPackages.codex-app
          raycast
        ])
        ++ (with pkgs.brewCasks; [
          aqua-voice
          zed
        ]);
    };
  };
}
