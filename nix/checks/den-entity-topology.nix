{
  den,
  flake,
  inputs,
  lib,
  pkgs,
}:
let
  sort = lib.sort builtins.lessThan;
  username = "constantan";

  hostEntries = [
    den.hosts.aarch64-darwin.constantan
    den.hosts.x86_64-linux.wsl
    den.hosts.aarch64-linux.wsl-aarch64
  ];
  userEntries = map (host: host.users.${username}) hostEntries;
  homeEntries = [
    den.homes.x86_64-linux."${username}@standalone-linux"
    den.homes.aarch64-linux."${username}@standalone-linux"
    den.homes.x86_64-linux."${username}@standalone-wsl"
    den.homes.aarch64-linux."${username}@standalone-wsl"
  ];
  wslUserGroups = sort flake.nixosConfigurations.wsl.config.users.users.${username}.extraGroups;

  describeHost = host: {
    inherit (host) class hostName system;
    aspect = host.aspect.name;
    intoAttr = host.intoAttr;
    environment = host.dotfiles.environment;
  };
  describeUser = user: {
    inherit (user) classes userName;
    aspect = user.aspect.name;
    primary = user.dotfiles.primary;
    shell = user.dotfiles.shell;
  };
  describeHome =
    home:
    let
      publicName = lib.last home.intoAttr;
      output = flake.homeConfigurations.${publicName};
    in
    {
      inherit (home) class system userName;
      aspect = home.aspect.name;
      intoAttr = home.intoAttr;
      environment = home.dotfiles.environment;
      standalone = home.dotfiles.standalone;
      osConfigIsNull = output.options._module.args.value.osConfig == null;
      syntheticHost = {
        inherit (home.host) name system;
        classless = !(home.host ? class);
      };
      syntheticUser = {
        inherit (home.user) classes userName;
      };
    };

  isolationEval = lib.evalModules {
    specialArgs = { inherit inputs; };
    modules = [
      inputs.den.flakeOutputs.flake
      inputs.den.flakeModule
      ../../modules/_tests/den-entity-topology.fixture.nix
    ];
  };
  isolationHome = isolationEval.config.flake.homeConfigurations.synthetic-isolation-probe;
  isolationVariables = isolationHome.config.home.sessionVariables;
  collisionRejected =
    !(builtins.tryEval (
      builtins.seq isolationEval.config.flake.nixosConfigurations.collision.config.warnings null
    )).success;

  actual = {
    scopeCount =
      builtins.length hostEntries + builtins.length userEntries + builtins.length homeEntries;
    hosts = map describeHost hostEntries;
    users = map describeUser userEntries;
    homes = map describeHome homeEntries;
    outputs = {
      darwin = sort (builtins.attrNames flake.darwinConfigurations);
      home = sort (builtins.attrNames flake.homeConfigurations);
      nixos = sort (builtins.attrNames flake.nixosConfigurations);
    };
    inherit wslUserGroups;
    wslHasNetworkmanager = lib.elem "networkmanager" wslUserGroups;
    wslHostnameOverride = flake.nixosConfigurations.wsl.config.wsl.wslConf.network.hostname;
    darwinPrimaryUser = flake.darwinConfigurations.constantan.config.system.primaryUser;
    syntheticIsolation = {
      host = isolationVariables.DEN_CONTEXT_HOST;
      user = isolationVariables.DEN_CONTEXT_USER;
      osConfig = isolationVariables.DEN_CONTEXT_OS_CONFIG;
      hostPolicyEvaluated = isolationVariables.DEN_HOST_POLICY_EVALUATED;
      hostPolicyLeaked = isolationVariables ? DEN_HOST_POLICY_LEAK;
      osConfigIsNull = isolationHome.options._module.args.value.osConfig == null;
    };
    inherit collisionRejected;
  };

  expected = {
    scopeCount = 10;
    hosts = [
      {
        class = "darwin";
        hostName = "constantan";
        system = "aarch64-darwin";
        aspect = "host/constantan";
        intoAttr = [
          "darwinConfigurations"
          "constantan"
        ];
        environment = "darwin";
      }
      {
        class = "nixos";
        hostName = "wsl";
        system = "x86_64-linux";
        aspect = "host/wsl";
        intoAttr = [
          "nixosConfigurations"
          "wsl"
        ];
        environment = "wsl";
      }
      {
        class = "nixos";
        hostName = "wsl-aarch64";
        system = "aarch64-linux";
        aspect = "host/wsl-aarch64";
        intoAttr = [
          "nixosConfigurations"
          "wsl-aarch64"
        ];
        environment = "wsl";
      }
    ];
    users = [
      {
        classes = [ "homeManager" ];
        userName = username;
        aspect = "user/constantan";
        primary = true;
        shell = "zsh";
      }
      {
        classes = [ "homeManager" ];
        userName = username;
        aspect = "user/constantan";
        primary = true;
        shell = "zsh";
      }
      {
        classes = [ "homeManager" ];
        userName = username;
        aspect = "user/constantan";
        primary = true;
        shell = "zsh";
      }
    ];
    homes = [
      {
        class = "homeManager";
        system = "x86_64-linux";
        userName = username;
        aspect = "home/standalone-linux";
        intoAttr = [
          "homeConfigurations"
          "${username}@linux-x86_64"
        ];
        environment = "linux";
        standalone = true;
        osConfigIsNull = true;
        syntheticHost = {
          name = "standalone-linux";
          system = "x86_64-linux";
          classless = true;
        };
        syntheticUser = {
          userName = username;
          classes = [ "homeManager" ];
        };
      }
      {
        class = "homeManager";
        system = "aarch64-linux";
        userName = username;
        aspect = "home/standalone-linux";
        intoAttr = [
          "homeConfigurations"
          "${username}@linux-aarch64"
        ];
        environment = "linux";
        standalone = true;
        osConfigIsNull = true;
        syntheticHost = {
          name = "standalone-linux";
          system = "aarch64-linux";
          classless = true;
        };
        syntheticUser = {
          userName = username;
          classes = [ "homeManager" ];
        };
      }
      {
        class = "homeManager";
        system = "x86_64-linux";
        userName = username;
        aspect = "home/standalone-wsl";
        intoAttr = [
          "homeConfigurations"
          "${username}@wsl-x86_64"
        ];
        environment = "wsl";
        standalone = true;
        osConfigIsNull = true;
        syntheticHost = {
          name = "standalone-wsl";
          system = "x86_64-linux";
          classless = true;
        };
        syntheticUser = {
          userName = username;
          classes = [ "homeManager" ];
        };
      }
      {
        class = "homeManager";
        system = "aarch64-linux";
        userName = username;
        aspect = "home/standalone-wsl";
        intoAttr = [
          "homeConfigurations"
          "${username}@wsl-aarch64"
        ];
        environment = "wsl";
        standalone = true;
        osConfigIsNull = true;
        syntheticHost = {
          name = "standalone-wsl";
          system = "aarch64-linux";
          classless = true;
        };
        syntheticUser = {
          userName = username;
          classes = [ "homeManager" ];
        };
      }
    ];
    outputs = {
      darwin = [ "constantan" ];
      home = [
        "constantan@linux-aarch64"
        "constantan@linux-x86_64"
        "constantan@wsl-aarch64"
        "constantan@wsl-x86_64"
      ];
      nixos = [
        "wsl"
        "wsl-aarch64"
      ];
    };
    wslUserGroups = [
      "docker"
      "wheel"
    ];
    wslHasNetworkmanager = false;
    wslHostnameOverride = "";
    darwinPrimaryUser = username;
    syntheticIsolation = {
      host = "standalone-wsl";
      user = "tux";
      osConfig = "null";
      hostPolicyEvaluated = "1";
      hostPolicyLeaked = false;
      osConfigIsNull = true;
    };
    collisionRejected = true;
  };
in
assert lib.assertMsg (actual == expected) ''
  Den entity topology mismatch:
  expected ${builtins.toJSON expected}
  actual ${builtins.toJSON actual}
'';
pkgs.runCommand "den-entity-topology-tests" { } ''touch "$out"''
