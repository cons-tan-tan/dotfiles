{
  entityContexts,
  flake,
  lib,
  pkgs,
}:
let
  guidancePayload = import ../../agents/guidance/_interface/payload.nix;
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
      staticResources = lib.sort builtins.lessThan (
        builtins.attrNames config.dotfiles.windows.staticResources
      );
      activations = {
        files = config.home.activation.deployWindowsCompanion.after;
        static = config.home.activation.deployWindowsCompanionStatic.after;
      };
      destinations = {
        claude = map (file: file.destination) config.dotfiles.windows.deployments.claude.files;
        git = map (file: file.destination) config.dotfiles.windows.deployments.git.files;
        gpg = map (file: file.destination) config.dotfiles.windows.deployments.gpg.files;
      };
      staticDestinations = lib.mapAttrs (_name: resource: {
        files = map (file: file.destination) resource.files;
        trees = map (tree: tree.destination) resource.trees;
      }) config.dotfiles.windows.staticResources;
      staticSource = (lib.head config.dotfiles.windows.staticResources.guidance.files).source;
    };
  integratedConfig =
    context:
    flake.nixosConfigurations.${context.nixosWsl}.config.home-manager.users.${context.username};
  standaloneConfig = context: flake.homeConfigurations.${context.home.wsl}.config;
  wingetSource =
    config:
    let
      files = config.dotfiles.windows.deployments.winget.files;
      file = lib.findFirst (candidate: candidate.destination == ".config/dev.winget") null files;
    in
    if file == null then
      throw "Windows class contract: dev.winget deployment is missing"
    else
      file.source;
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
  expectedFor = context: {
    metadata = {
      inherit (context) environment source;
      inherit (context.windows) enable homedir username;
      linuxHomedir = context.homedir;
      wingetEnabled = true;
    };
    deployments = [
      "claude"
      "git"
      "gpg"
      "powershell"
      "winget"
    ];
    staticResources = [
      "claude"
      "guidance"
      "skills"
    ];
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
    staticDestinations = {
      claude = {
        files = [ ];
        trees = [
          ".claude/commands"
          ".claude/output-styles"
          ".claude/hooks"
        ];
      };
      guidance = {
        files = [ ".claude/CLAUDE.md" ];
        trees = [ ".claude/rules" ];
      };
      skills = {
        files = [ ];
        trees = [
          ".claude/skills"
          ".agents/skills"
        ];
      };
    };
    staticSource = "${context.source}/${guidancePayload.repositoryRelative.globalContext}";
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
  };
  # The generated files use each target package set, so this x86 check only
  # builds native outputs. The value contract above still evaluates both architectures.
  wingetSources = map wingetSource [
    (integratedConfig entityContexts.linuxX86)
    (standaloneConfig entityContexts.linuxX86)
  ];
  referenceConfig = integratedConfig entityContexts.linuxX86;
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
      integratedX86 = expectedFor entityContexts.linuxX86.contexts.nixosWsl;
      integratedAarch64 = expectedFor entityContexts.linuxAarch64.contexts.nixosWsl;
      standaloneX86 = expectedFor entityContexts.linuxX86.contexts.home.wsl;
      standaloneAarch64 = expectedFor entityContexts.linuxAarch64.contexts.home.wsl;
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
    sources = lib.concatStringsSep " " (map toString wingetSources);
  }
  ''
    for source in $sources; do
      for package_id in \
        ZedIndustries.Zed \
        BurntSushi.ripgrep.MSVC \
        sharkdp.fd \
        sharkdp.bat \
        eza-community.eza \
        jqlang.jq \
        ast-grep.ast-grep \
        junegunn.fzf; do
        count="$(rg --count --fixed-strings "id: $package_id" "$source")"
        test "$count" -eq 1
      done
    done

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
