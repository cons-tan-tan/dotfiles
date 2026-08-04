{
  den,
  features,
  ...
}:
{
  den.aspects.users.constantan = {
    name = "user/constantan";
    includes = [
      den.batteries.define-user
      den.batteries.host-aspects
      features.platform-user
      features.common-home
      features.agents-default
    ];
  };
}
