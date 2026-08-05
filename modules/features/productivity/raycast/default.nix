{ den, ... }:
{
  features.productivity-raycast = {
    name = "feature/productivity/raycast";
    includes = [
      (den.batteries.unfree [ "raycast" ])
    ];
    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.raycast ];
    };
  };
}
