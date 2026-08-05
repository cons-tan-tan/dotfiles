{ lib }:
{
  describe = target: {
    packageCount = builtins.length (
      builtins.filter (package: lib.getName package == "raycast") target.config.home.packages
    );
  };
  expected = facts: {
    packageCount = if facts.environment == "darwin" then 1 else 0;
  };
}
