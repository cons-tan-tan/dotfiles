{
  flake,
  inputs,
  lib,
  pkgs,
  username,
}:
let
  canonicalSource = "/home/${username}/ghq/github.com/cons-tan-tan/dotfiles";
  describeWsl = config: {
    metadata = {
      inherit (config.dotfiles.windows)
        enable
        environment
        homedir
        linuxHomedir
        source
        username
        wingetEnabled
        ;
    };
    deployments = lib.sort builtins.lessThan (builtins.attrNames config.dotfiles.windows.deployments);
    staticResources = builtins.attrNames config.dotfiles.windows.staticResources;
    activations = {
      files = config.home.activation.deployWindowsCompanion.after;
      static = config.home.activation.deployWindowsCompanionStatic.after;
    };
    destinations = map (file: file.destination) config.dotfiles.windows.deployments.git.files;
    staticSource = (lib.head config.dotfiles.windows.staticResources.claude.files).source;
  };
  integrated =
    systemName:
    describeWsl flake.nixosConfigurations.${systemName}.config.home-manager.users.${username};
  standalone = system: describeWsl flake.homeConfigurations."${username}@wsl-${system}".config;
  expectedFor = source: {
    metadata = {
      enable = true;
      environment = "wsl";
      homedir = "/mnt/c/Users/zhouc";
      linuxHomedir = "/home/${username}";
      inherit source;
      username = "zhouc";
      wingetEnabled = true;
    };
    deployments = [
      "claude"
      "git"
      "gpg"
      "powershell"
      "winget"
    ];
    staticResources = [ "claude" ];
    activations = {
      files = [ "writeBoundary" ];
      static = [ "linkGeneration" ];
    };
    destinations = [
      ".gitconfig"
      ".gitconfig.d/commit-template"
      ".config/git/ignore"
    ];
    staticSource = "${source}/agents/context/global.md";
  };
  actual = {
    delivery = {
      integratedX86 = integrated "wsl";
      integratedAarch64 = integrated "wsl-aarch64";
      standaloneX86 = standalone "x86_64";
      standaloneAarch64 = standalone "aarch64";
    };
    isolation = {
      linux = flake.homeConfigurations."${username}@linux-x86_64".config.dotfiles ? windows;
      darwin =
        flake.darwinConfigurations.${username}.config.home-manager.users.${username}.dotfiles ? windows;
    };
  };
  integratedExpected = expectedFor (toString inputs.self.outPath);
  standaloneExpected = expectedFor canonicalSource;
  expected = {
    delivery = {
      integratedX86 = integratedExpected;
      integratedAarch64 = integratedExpected;
      standaloneX86 = standaloneExpected;
      standaloneAarch64 = standaloneExpected;
    };
    isolation = {
      linux = false;
      darwin = false;
    };
  };
in
assert lib.assertMsg (actual == expected) ''
  Windows class contract mismatch:
  expected ${builtins.toJSON expected}
  actual ${builtins.toJSON actual}
'';
pkgs.runCommand "windows-class-contract" { } ''touch "$out"''
