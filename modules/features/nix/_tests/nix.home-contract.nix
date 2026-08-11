{ ... }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      registry = target.config.nix.registry.dotfiles;
      guard = config.dotfiles.agentCommandPolicyCompiled.guardPolicy;
      packageCount =
        package: builtins.length (builtins.filter (candidate: candidate == package) config.home.packages);
    in
    {
      registry = {
        fromId = registry.from.id;
        fromType = registry.from.type;
        path = toString registry.to.path;
        toType = registry.to.type;
      };
      tooling = {
        comma = config.programs.nix-index-database.comma.enable;
        nixd = packageCount pkgs.nixd;
      };
      commandPolicy = {
        schemaVersion = guard.schemaVersion;
        grammarExecutables = builtins.attrNames guard.commandGrammars;
      };
    };
  expected = facts: {
    registry = {
      fromId = "dotfiles";
      fromType = "indirect";
      path = facts.registryPath;
      toType = "path";
    };
    tooling = {
      comma = true;
      nixd = 1;
    };
    commandPolicy = {
      schemaVersion = 3;
      grammarExecutables = [
        "nh"
        "nix"
        "nix-build"
        "nix-channel"
        "nix-collect-garbage"
        "nix-env"
        "nix-instantiate"
        "nix-shell"
        "nix-store"
      ];
    };
  };
}
