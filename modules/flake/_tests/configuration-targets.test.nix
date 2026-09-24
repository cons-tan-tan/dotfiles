{
  configurationTargets,
  flake,
  lib,
  ...
}:
let
  homeIdentity = home: {
    inherit (home.config.home) username homeDirectory;
    inherit (home.config.dotfiles.platform) environment standalone windows;
  };
  expectedIdentity = context: {
    inherit (context) username;
    homeDirectory = context.homedir;
    inherit (context) environment standalone windows;
  };
  homes =
    lib.concatMap
      (
        targets:
        map (context: {
          actual = homeIdentity flake.homeConfigurations.${context.outputName};
          expected = expectedIdentity context;
        }) (builtins.attrValues targets.contexts.home)
      )
      [
        configurationTargets.x86_64-linux
        configurationTargets.aarch64-linux
      ];
  hosts = [
    {
      context = configurationTargets.aarch64-darwin.contexts.darwin;
      config = flake.darwinConfigurations.constantan.config;
    }
    {
      context = configurationTargets.x86_64-linux.contexts.nixosWsl;
      config = flake.nixosConfigurations.wsl.config;
    }
    {
      context = configurationTargets.aarch64-linux.contexts.nixosWsl;
      config = flake.nixosConfigurations.wsl-aarch64.config;
    }
  ];
in
{
  testEveryStandaloneTargetMatchesItsActualConfiguration = {
    expr = map (home: home.actual) homes;
    expected = map (home: home.expected) homes;
  };
  testEveryIntegratedTargetMatchesItsActualConfiguration = {
    expr = map (
      { config, context }: homeIdentity { config = config.home-manager.users.${context.username}; }
    ) hosts;
    expected = map ({ context, ... }: expectedIdentity context) hosts;
  };
  testStandaloneHomesHaveNoHostConfiguration = {
    expr = builtins.all (home: home.options._module.args.value.osConfig == null) (
      builtins.attrValues flake.homeConfigurations
    );
    expected = true;
  };
}
