{ }:
{
  describe =
    target:
    let
      registry = target.config.nix.registry.dotfiles;
    in
    {
      fromId = registry.from.id;
      fromType = registry.from.type;
      path = toString registry.to.path;
      toType = registry.to.type;
    };
  expected = facts: {
    fromId = "dotfiles";
    fromType = "indirect";
    path = facts.registryPath;
    toType = "path";
  };
}
