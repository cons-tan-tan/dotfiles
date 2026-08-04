{ den, inputs, ... }:
let
  username = "constantan";
  linuxSource = "/home/${username}/ghq/github.com/cons-tan-tan/dotfiles";
  windows = {
    enable = true;
    username = "zhouc";
    homedir = "/mnt/c/Users/zhouc";
  };

  mkUser = aspect: {
    classes = [ "homeManager" ];
    inherit aspect;
    dotfiles = {
      primary = true;
      shell = "zsh";
    };
  };

  mkWslHost = aspect: {
    inherit aspect;
    wsl.enable = true;
    dotfiles = {
      environment = "wsl";
      source = toString inputs.self.outPath;
      inherit windows;
    };
    users.${username} = mkUser den.aspects.users.constantan;
  };

  mkHome =
    {
      aspect,
      environment,
      intoAttr,
      windows ? { },
    }:
    {
      inherit aspect intoAttr;
      dotfiles = {
        inherit environment windows;
        source = linuxSource;
      };
    };
in
{
  den.hosts.aarch64-darwin.constantan = {
    aspect = den.aspects.hosts.constantan;
    dotfiles = {
      environment = "darwin";
      source = "/Users/${username}/ghq/github.com/cons-tan-tan/dotfiles";
    };
    users.${username} = mkUser den.aspects.users.constantan;
  };

  den.hosts.x86_64-linux.wsl = mkWslHost den.aspects.hosts.wsl;
  den.hosts.aarch64-linux.wsl-aarch64 = mkWslHost den.aspects.hosts.wsl-aarch64;

  den.homes.x86_64-linux."${username}@standalone-linux" = mkHome {
    aspect = den.aspects.homes.standalone-linux;
    environment = "linux";
    intoAttr = [
      "homeConfigurations"
      "${username}@linux-x86_64"
    ];
  };
  den.homes.aarch64-linux."${username}@standalone-linux" = mkHome {
    aspect = den.aspects.homes.standalone-linux;
    environment = "linux";
    intoAttr = [
      "homeConfigurations"
      "${username}@linux-aarch64"
    ];
  };
  den.homes.x86_64-linux."${username}@standalone-wsl" = mkHome {
    aspect = den.aspects.homes.standalone-wsl;
    environment = "wsl";
    intoAttr = [
      "homeConfigurations"
      "${username}@wsl-x86_64"
    ];
    inherit windows;
  };
  den.homes.aarch64-linux."${username}@standalone-wsl" = mkHome {
    aspect = den.aspects.homes.standalone-wsl;
    environment = "wsl";
    intoAttr = [
      "homeConfigurations"
      "${username}@wsl-aarch64"
    ];
    inherit windows;
  };
}
