{
  expected,
  owner,
}:
{
  assertion = owner.dotfiles.environment == expected;
  message = "dotfiles ${expected} environment aspect requires owner.dotfiles.environment = ${expected}";
}
