{
  describe = target: {
    inherit (target.config.dotfiles.platform)
      environment
      source
      standalone
      windows
      ;
  };
  expected = facts: {
    inherit (facts)
      environment
      standalone
      windows
      ;
    source = facts.registryPath;
  };
}
