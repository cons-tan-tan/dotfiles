{
  den,
  inputs,
  lib,
  pkgs,
}:
let
  hostEntries = lib.concatMap builtins.attrValues (builtins.attrValues den.hosts);
  userEntries = lib.concatMap (host: builtins.attrValues host.users) hostEntries;
  homeEntries = lib.concatMap builtins.attrValues (builtins.attrValues den.homes);

  isolationEval = lib.evalModules {
    specialArgs = { inherit inputs; };
    modules = [
      inputs.den.flakeOutputs.flake
      inputs.den.flakeModule
      ./topology.fixture.nix
    ];
  };
  isolationHome = isolationEval.config.flake.homeConfigurations.synthetic-isolation-probe;
  isolationVariables = isolationHome.config.home.sessionVariables;
  actual = {
    aspectOwnership = {
      hosts = builtins.all (host: host.aspect.name == "host/${host.hostName}") hostEntries;
      users = builtins.all (user: user.aspect.name == "user/${user.userName}") userEntries;
      homes = builtins.all (
        home: home.aspect.name == "home/standalone-${home.dotfiles.environment}"
      ) homeEntries;
    };
    syntheticIsolation = {
      host = isolationVariables.DEN_CONTEXT_HOST;
      user = isolationVariables.DEN_CONTEXT_USER;
      osConfig = isolationVariables.DEN_CONTEXT_OS_CONFIG;
      hostPolicyEvaluated = isolationVariables.DEN_HOST_POLICY_EVALUATED;
      hostPolicyLeaked = isolationVariables ? DEN_HOST_POLICY_LEAK;
      osConfigIsNull = isolationHome.options._module.args.value.osConfig == null;
    };
  };
  expected = {
    aspectOwnership = {
      hosts = true;
      users = true;
      homes = true;
    };
    syntheticIsolation = {
      host = "standalone-wsl";
      user = "tux";
      osConfig = "null";
      hostPolicyEvaluated = "1";
      hostPolicyLeaked = false;
      osConfigIsNull = true;
    };
  };
in
assert lib.assertMsg (actual == expected) ''
  Den entity topology mismatch:
  expected ${builtins.toJSON expected}
  actual ${builtins.toJSON actual}
'';
pkgs.runCommand "den-entity-topology-tests" { } ''touch "$out"''
