_: {
  # Descriptive metadata is safe to inherit globally. Fields that alter tools,
  # hooks, models, or invocation require an explicit per-skill opt-in.
  defaultInheritedFrontmatterFields = [
    "name"
    "description"
    "license"
    "compatibility"
    "metadata"
  ];
}
