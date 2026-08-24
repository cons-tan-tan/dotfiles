{
  entityContexts,
  flake,
  lib,
  pkgs,
}:
let
  describeWsl = config: {
    activations = {
      files = config.home.activation.deployWindowsCompanion.after;
      static = config.home.activation.deployWindowsCompanionStatic.after;
    };
  };
  integratedConfig =
    context:
    flake.nixosConfigurations.${context.nixosWsl}.config.home-manager.users.${context.username};
  standaloneConfig = context: flake.homeConfigurations.${context.home.wsl}.config;
  referenceConfig = integratedConfig entityContexts.linuxX86;
  deploymentSource =
    config: deploymentName: destination:
    let
      files = config.dotfiles.windows.deployments.${deploymentName}.files;
      file = lib.findFirst (candidate: candidate.destination == destination) null files;
    in
    if file == null then
      throw "Windows class contract: ${deploymentName} deployment is missing ${destination}"
    else
      file.source;
  expectedDelivery = {
    activations = {
      files = [ "writeBoundary" ];
      static = [ "linkGeneration" ];
    };
  };
  actual = {
    delivery = {
      integratedX86 = describeWsl (integratedConfig entityContexts.linuxX86);
      integratedAarch64 = describeWsl (integratedConfig entityContexts.linuxAarch64);
      standaloneX86 = describeWsl (standaloneConfig entityContexts.linuxX86);
      standaloneAarch64 = describeWsl (standaloneConfig entityContexts.linuxAarch64);
    };
    isolation = {
      linux = flake.homeConfigurations.${entityContexts.linuxX86.home.linux}.config.dotfiles ? windows;
      darwin =
        flake.darwinConfigurations.${entityContexts.darwin.darwin}.config.home-manager.users.${entityContexts.darwin.username}.dotfiles
        ? windows;
    };
    staticResources =
      lib.genAttrs
        [
          "claude"
          "guidance"
          "skills"
        ]
        (
          name:
          let
            resource = referenceConfig.dotfiles.windows.staticResources.${name};
          in
          resource.files != [ ] || resource.trees != [ ]
        );
  };
  claudeSettingsSource = deploymentSource referenceConfig "claude" ".claude/settings.json";
  gitConfigSource = deploymentSource referenceConfig "git" ".gitconfig";
  gitCommitTemplateSource = deploymentSource referenceConfig "git" ".gitconfig.d/commit-template";
  gitIgnoreSource = deploymentSource referenceConfig "git" ".config/git/ignore";
  gpgAgentSource = deploymentSource referenceConfig "gpg" "AppData/Roaming/gnupg/gpg-agent.conf";
  gpgConfigSource = deploymentSource referenceConfig "gpg" "AppData/Roaming/gnupg/gpg.conf";
  gpgSshcontrolSource = deploymentSource referenceConfig "gpg" "AppData/Roaming/gnupg/sshcontrol";
  windowsUsername = entityContexts.linuxX86.contexts.nixosWsl.windows.username;
  expected = {
    delivery = {
      integratedX86 = expectedDelivery;
      integratedAarch64 = expectedDelivery;
      standaloneX86 = expectedDelivery;
      standaloneAarch64 = expectedDelivery;
    };
    isolation = {
      linux = false;
      darwin = false;
    };
    staticResources = {
      claude = true;
      guidance = true;
      skills = true;
    };
  };
in
assert lib.assertMsg (actual == expected) ''
  Windows class contract mismatch:
  expected ${builtins.toJSON expected}
  actual ${builtins.toJSON actual}
'';
pkgs.runCommand "windows-class-contract"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.ripgrep
    ];
    inherit
      claudeSettingsSource
      gitCommitTemplateSource
      gitConfigSource
      gitIgnoreSource
      gpgAgentSource
      gpgConfigSource
      gpgSshcontrolSource
      ;
  }
  ''
    jq --exit-status '
      ((.permissions.allow // []) | all(startswith("Bash(") | not))
      and ((.permissions | has("deny")) | not)
    ' "$claudeSettingsSource" >/dev/null

    rg --fixed-strings 'signingkey = "6250E02A31E09AFE"' "$gitConfigSource"
    rg --fixed-strings 'gpgsign = true' "$gitConfigSource"
    rg --fixed-strings 'format = "openpgp"' "$gitConfigSource"
    rg --fixed-strings ${lib.escapeShellArg "template = \"C:/Users/${windowsUsername}/.gitconfig.d/commit-template\""} "$gitConfigSource"
    rg --fixed-strings '# feat: 新しい機能' "$gitCommitTemplateSource"
    rg --fixed-strings 'CLAUDE.local.md' "$gitIgnoreSource"

    rg --fixed-strings 'default-cache-ttl 43200' "$gpgAgentSource"
    rg --fixed-strings 'enable-ssh-support' "$gpgAgentSource"
    rg --fixed-strings 'pinentry-program C:/Program Files/Gpg4win/bin/pinentry.exe' "$gpgAgentSource"
    rg --fixed-strings 'use-agent' "$gpgConfigSource"
    rg --fixed-strings '60DE257CE1919B3D6DCF4E6E239CD1FFE63B45FD' "$gpgSshcontrolSource"

    touch "$out"
  ''
