{
  entityContexts,
  flake,
  inputs,
  lib,
  pkgs,
}:
let
  username = "constantan";
  canonicalSource = "/home/${username}/ghq/github.com/cons-tan-tan/dotfiles";
  describeWsl =
    config:
    let
      platform = config.dotfiles.platform;
    in
    {
      metadata = {
        inherit (platform) environment source;
        inherit (platform.windows) enable homedir username;
        linuxHomedir = config.home.homeDirectory;
        inherit (config.dotfiles.windows) wingetEnabled;
      };
      deployments = lib.sort builtins.lessThan (builtins.attrNames config.dotfiles.windows.deployments);
      staticResources = builtins.attrNames config.dotfiles.windows.staticResources;
      activations = {
        files = config.home.activation.deployWindowsCompanion.after;
        static = config.home.activation.deployWindowsCompanionStatic.after;
      };
      destinations = {
        claude = map (file: file.destination) config.dotfiles.windows.deployments.claude.files;
        git = map (file: file.destination) config.dotfiles.windows.deployments.git.files;
        gpg = map (file: file.destination) config.dotfiles.windows.deployments.gpg.files;
      };
      staticSource = (lib.head config.dotfiles.windows.staticResources.claude.files).source;
    };
  integrated =
    context:
    describeWsl (
      flake.nixosConfigurations.${context.nixosWsl}.config.home-manager.users.${context.username}
    );
  standalone = context: describeWsl flake.homeConfigurations.${context.home.wsl}.config;
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
    destinations = {
      claude = [ ".claude/settings.json" ];
      git = [
        ".gitconfig"
        ".gitconfig.d/commit-template"
        ".config/git/ignore"
      ];
      gpg = [
        "AppData/Roaming/gnupg/gpg-agent.conf"
        "AppData/Roaming/gnupg/gpg.conf"
        "AppData/Roaming/gnupg/sshcontrol"
      ];
    };
    staticSource = "${source}/agents/context/global.md";
  };
  actual = {
    delivery = {
      integratedX86 = integrated entityContexts.linuxX86;
      integratedAarch64 = integrated entityContexts.linuxAarch64;
      standaloneX86 = standalone entityContexts.linuxX86;
      standaloneAarch64 = standalone entityContexts.linuxAarch64;
    };
    isolation = {
      linux = flake.homeConfigurations.${entityContexts.linuxX86.home.linux}.config.dotfiles ? windows;
      darwin =
        flake.darwinConfigurations.${entityContexts.darwin.darwin}.config.home-manager.users.${entityContexts.darwin.username}.dotfiles
        ? windows;
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
