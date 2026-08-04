{
  flake,
  inputs,
  lib,
  pkgs,
}:
let
  username = "constantan";
  canonicalLinux = "/home/${username}/ghq/github.com/cons-tan-tan/dotfiles";
  canonicalDarwin = "/Users/${username}/ghq/github.com/cons-tan-tan/dotfiles";

  standalone = name: {
    config = flake.homeConfigurations.${name}.config;
    inherit (flake.homeConfigurations.${name}) pkgs;
  };
  integratedWsl = name: {
    config = flake.nixosConfigurations.${name}.config.home-manager.users.${username};
    inherit (flake.nixosConfigurations.${name}) pkgs;
  };
  integratedDarwin = {
    config = flake.darwinConfigurations.${username}.config.home-manager.users.${username};
    inherit (flake.darwinConfigurations.${username}) pkgs;
  };

  entries = {
    "${username}@linux-x86_64" = standalone "${username}@linux-x86_64";
    "${username}@linux-aarch64" = standalone "${username}@linux-aarch64";
    "${username}@wsl-x86_64" = standalone "${username}@wsl-x86_64";
    "${username}@wsl-aarch64" = standalone "${username}@wsl-aarch64";
    wsl = integratedWsl "wsl";
    wsl-aarch64 = integratedWsl "wsl-aarch64";
    darwin = integratedDarwin;
  };

  describe =
    entry:
    let
      inherit (entry) config;
      entryPkgs = entry.pkgs;
      packages = config.home.packages;
      systemdServices = lib.attrByPath [ "systemd" "user" "services" ] { } config;
      systemdTimers = lib.attrByPath [ "systemd" "user" "timers" ] { } config;
      launchdAgents = lib.attrByPath [ "launchd" "agents" ] { } config;
      pinentry = config.services.gpg-agent.pinentry.package;
      hasPackage = package: builtins.elem package packages;
      awsActivation = config.home.activation.awsConfigMerge;
      trashActivation = config.home.activation.trashDirectory;
      ghExtensions = config.programs.gh.extensions;
      registry = config.nix.registry.dotfiles;
      agentEnvironment = config.dotfiles.agentEnvironment;
      commandPolicy = config.dotfiles.agentCommandPolicyCompiled;
      claudeActivation = config.home.activation.claudeHooksDirectoryMigration;
      codexActivation = config.home.activation.codexHooksConfig;
      packageNames = map lib.getName packages;
      skillNamesFor =
        prefix:
        map (lib.removePrefix prefix) (
          builtins.filter (lib.hasPrefix prefix) (builtins.attrNames config.home.file)
        );
      commonPackages =
        (with entryPkgs; [
          ast-grep
          basedpyright
          bat
          ccusage
          eza
          fastfetch
          fd
          ffmpeg
          fzf
          gemini-cli
          ghq
          github-copilot-cli
          git-cliff
          go
          gopass
          jq
          mozuku-lsp
          neovim
          ni
          nixd
          nodejs
          pinact
          pnpm
          reuse
          ripgrep
          ruff
          rustup
          sops
          trufflehog
          ty
          uv
          watchexec
          yazi
          zizmor
        ])
        ++ (with entryPkgs.dotfilesPackages; [
          agent-browser
          agent-slack
          difit
          gha-lint
          shellfirm
        ]);
    in
    {
      identity = {
        inherit (config.home) homeDirectory stateVersion username;
        releaseCheck = config.home.enableNixpkgsReleaseCheck;
        system = entryPkgs.stdenv.hostPlatform.system;
      };
      programs = {
        comma = config.programs.nix-index-database.comma.enable;
        direnv = config.programs.direnv.enable;
        gh = config.programs.gh.enable;
        git = config.programs.git.enable;
        gpg = config.programs.gpg.enable;
        homeManager = config.programs.home-manager.enable;
        starship = config.programs.starship.enable;
        starshipPreset = builtins.elem "nerd-font-symbols" config.programs.starship.presets;
        starshipZsh = config.programs.starship.enableZshIntegration;
        zoxide = config.programs.zoxide.enable;
        zoxideZsh = config.programs.zoxide.enableZshIntegration;
        zsh = config.programs.zsh.enable;
        direnvNix = config.programs.direnv.nix-direnv.enable;
        direnvZsh = config.programs.direnv.enableZshIntegration;
        gpgAgentZsh = config.services.gpg-agent.enableZshIntegration;
      };
      agents = {
        environment = {
          inherit (agentEnvironment) environment source;
          hcomAbsent = config.dotfiles.agentIntegrations.hcom == null;
        };
        programs = {
          claude = config.programs.claude-code.enable;
          hunk = config.programs.hunk.enable;
          opencode = config.programs.opencode.enable;
        };
        packages = {
          claude = builtins.elem "claude-code" packageNames;
          codex = builtins.elem "codex-wrapped" packageNames;
          herdr = builtins.elem "herdr" packageNames;
          hunk = hasPackage config.programs.hunk.package;
          pi = builtins.elem "pi" packageNames;
        };
        files = {
          claudeSettings = config.home.file ? ".claude/settings.json";
          codexHooks = config.home.file ? ".codex/hooks.json";
          guidance = config.home.file ? ".agents/context";
          herdr = config.home.file ? ".config/herdr/config.toml";
          opencode = config.home.file ? ".config/opencode/plugins/herdr-agent-state.js";
          pi = config.home.file ? ".pi/agent/settings.json";
        };
        skills = {
          agents = skillNamesFor ".agents/skills/";
          claude = skillNamesFor ".claude/skills/";
        };
        policy = {
          schemaVersion = commandPolicy.guardPolicy.schemaVersion;
          allowsRg = lib.any (rule: rule.argvPrefix == [ "rg" ]) commandPolicy.prefixRules;
          deniesTrashEmpty = lib.any (
            rule: rule.argvPrefix == [ "trash-empty" ] && rule.decision == "deny"
          ) commandPolicy.guardPolicy.exact;
          inherit (commandPolicy.guardPolicy.unknown)
            dynamicExecutable
            dynamicRelevantOption
            parseError
            ;
        };
        activation = {
          claudeBeforeCheckLinkTargets = claudeActivation.before == [ "checkLinkTargets" ];
          codexAfterLinkGeneration = codexActivation.after == [ "linkGeneration" ];
        };
        hunkUsesPlatformRuntime =
          config.programs.hunk.package == (
            if agentEnvironment.environment == "wsl" then
              entryPkgs.dotfilesPackages.hunk.wslRuntime
            else
              entryPkgs.dotfilesPackages.hunk.package
          );
      };
      sourceControl = {
        signingKey = config.programs.git.signing.key;
        signByDefault = config.programs.git.signing.signByDefault;
        gitWtZsh = lib.hasInfix "git-wt --init zsh" config.programs.zsh.initContent;
        ghExtensions = {
          apiGet = builtins.elem entryPkgs.dotfilesPackages.gh-api-get ghExtensions;
          do = builtins.elem entryPkgs.gh-do ghExtensions;
          poi = builtins.elem entryPkgs.gh-poi ghExtensions;
        };
        settings = {
          autocrlf = config.programs.git.settings.core.autocrlf;
          defaultBranch = config.programs.git.settings.init.defaultBranch;
          editor = config.programs.git.settings.core.editor;
          worktreeBase = config.programs.git.settings.wt.basedir;
        };
        ignoresLocalClaude = builtins.elem "CLAUDE.local.md" config.programs.git.ignores;
      };
      files = {
        sshConfig = config.home.file ? ".ssh/config";
        sshCommon = config.home.file ? ".ssh/config.d/10-common.conf";
        sshPrivateAbsent = !(config.home.file ? ".ssh/config.d/50-private.conf");
        sshConfigIncludesFragments =
          lib.hasInfix "Include ~/.ssh/config.d/*.conf"
            config.home.file.".ssh/config".text;
        sshCommonHasGithub =
          lib.hasInfix "Host github.com"
            config.home.file.".ssh/config.d/10-common.conf".text;
      };
      activation = {
        aws = {
          afterWriteBoundary = awsActivation.after == [ "writeBoundary" ];
          usesRun = lib.hasPrefix "run " awsActivation.data;
          reconcilesConfig = lib.hasInfix "aws-config-reconcile" awsActivation.data;
        };
        trash = {
          afterWriteBoundary = trashActivation.after == [ "writeBoundary" ];
          usesRun = lib.hasPrefix "run " trashActivation.data;
          createsFreedesktopDirectories =
            lib.hasInfix "Trash/files" trashActivation.data && lib.hasInfix "Trash/info" trashActivation.data;
          restrictsPermissions = lib.hasInfix "chmod 0700" trashActivation.data;
        };
      };
      cloud.gcloud = {
        default = config.xdg.configFile."gcloud/configurations/config_default".text == "[core]\n";
        personal =
          config.xdg.configFile."gcloud/configurations/config_personal".text
          == "[core]\naccount=zhouchengt@gmail.com\n";
        tdu =
          config.xdg.configFile."gcloud/configurations/config_tdu".text
          == "[core]\naccount=makisyu.tdu@gmail.com\n";
      };
      security.gpg = {
        cacheTtl = config.services.gpg-agent.defaultCacheTtl;
        maxCacheTtl = config.services.gpg-agent.maxCacheTtl;
        sshSupport = config.services.gpg-agent.enableSshSupport;
        sshKeys = config.services.gpg-agent.sshKeys;
        windowsPinentry = lib.hasInfix "Gpg4win/bin/pinentry.exe" config.services.gpg-agent.extraConfig;
      };
      registry = {
        fromId = registry.from.id;
        fromType = registry.from.type;
        path = toString registry.to.path;
        toType = registry.to.type;
      };
      packages = {
        ax = hasPackage inputs.ax.packages.${entryPkgs.stdenv.hostPlatform.system}.ax;
        aws = hasPackage entryPkgs.awscli2;
        awsLogin = builtins.any (package: lib.getName package == "aws-login") packages;
        curl = hasPackage entryPkgs.curl;
        gcloud = hasPackage entryPkgs.google-cloud-sdk;
        gitWt = hasPackage entryPkgs.git-wt;
        trash = hasPackage entryPkgs.trash-cli;
        common = builtins.all hasPackage commonPackages;
      };
      platform = {
        gpgPinentry = if pinentry == null then null else lib.getName pinentry;
        ghqSystemd = systemdServices ? ghq-fetch && systemdTimers ? ghq-fetch;
        ghqLaunchd = launchdAgents ? ghq-fetch;
        ghqSchedule =
          if launchdAgents ? ghq-fetch then
            launchdAgents.ghq-fetch.config.StartInterval == 600
            && lib.any (
              command: lib.hasInfix "ghq-fetch-all" command
            ) launchdAgents.ghq-fetch.config.ProgramArguments
          else
            systemdTimers.ghq-fetch.Timer.OnUnitActiveSec == "10min"
            && systemdServices.ghq-fetch.Service.TimeoutStartSec == 600
            && systemdServices.ghq-fetch.Service.Type == "oneshot"
            && lib.any (
              command: lib.hasInfix "ghq-fetch-all" command
            ) systemdServices.ghq-fetch.Service.ExecStart;
        ghqDurability =
          if launchdAgents ? ghq-fetch then
            launchdAgents.ghq-fetch.config.Nice == 10
            && launchdAgents.ghq-fetch.config.ProcessType == "Background"
          else
            systemdTimers.ghq-fetch.Timer.Persistent
            && systemdTimers.ghq-fetch.Timer.OnBootSec == "2min"
            && systemdTimers.ghq-fetch.Timer.RandomizedDelaySec == "30s"
            && builtins.elem "network-online.target" systemdServices.ghq-fetch.Unit.After
            && builtins.elem "network-online.target" systemdServices.ghq-fetch.Unit.Wants
            && systemdServices.ghq-fetch.Service.Nice == 10
            && systemdServices.ghq-fetch.Service.IOSchedulingClass == "idle";
        trashSystemd = systemdServices ? trash-gc && systemdTimers ? trash-gc;
        trashLaunchd = launchdAgents ? trash-gc;
        trashSchedule =
          if launchdAgents ? trash-gc then
            let
              calendar = builtins.head launchdAgents.trash-gc.config.StartCalendarInterval;
            in
            calendar.Hour == 3 && calendar.Minute == 0
          else
            systemdTimers.trash-gc.Timer.OnCalendar == "*-*-* 03:00:00";
        trashDurability =
          if launchdAgents ? trash-gc then
            launchdAgents.trash-gc.domain == "user"
            && launchdAgents.trash-gc.config.Nice == 10
            && launchdAgents.trash-gc.config.ProcessType == "Background"
          else
            systemdTimers.trash-gc.Timer.Persistent
            && systemdTimers.trash-gc.Timer.RandomizedDelaySec == "30min"
            && systemdServices.trash-gc.Service.Nice == 10
            && systemdServices.trash-gc.Service.IOSchedulingClass == "idle";
        wslAuthSockOverride = lib.any (
          command: lib.hasInfix "set-SSH_AUTH_SOCK-wsl" command
        ) systemdServices.set-SSH_AUTH_SOCK.Service.ExecStart;
      };
    };

  commonExpected = {
    agents = {
      programs = {
        claude = true;
        hunk = true;
        opencode = true;
      };
      packages = {
        claude = true;
        codex = true;
        herdr = true;
        hunk = true;
        pi = true;
      };
      files = {
        claudeSettings = true;
        codexHooks = true;
        guidance = true;
        herdr = true;
        opencode = true;
        pi = true;
      };
      skills = {
        agents = [
          "agent-browser"
          "agent-slack"
          "ast-grep"
          "ax"
          "commit"
          "difit"
          "difit-review"
          "drawio"
          "frontend-design"
          "hunk-review"
          "improve"
          "japanese-tech-writing"
          "missing-tools"
          "pptx"
        ];
        claude = [
          "agent-browser"
          "agent-slack"
          "ast-grep"
          "ax"
          "commit"
          "difit"
          "difit-review"
          "drawio"
          "frontend-design"
          "hunk-review"
          "improve"
          "japanese-tech-writing"
          "missing-tools"
          "pptx"
        ];
      };
      policy = {
        schemaVersion = 2;
        allowsRg = true;
        deniesTrashEmpty = true;
        dynamicExecutable = "deny";
        dynamicRelevantOption = "deny";
        parseError = "deny";
      };
      activation = {
        claudeBeforeCheckLinkTargets = true;
        codexAfterLinkGeneration = true;
      };
    };
    programs = {
      comma = true;
      direnv = true;
      gh = true;
      git = true;
      gpg = true;
      homeManager = true;
      starship = true;
      starshipPreset = true;
      starshipZsh = true;
      zoxide = true;
      zoxideZsh = true;
      zsh = true;
      direnvNix = true;
      direnvZsh = true;
      gpgAgentZsh = true;
    };
    sourceControl = {
      signingKey = "6250E02A31E09AFE";
      signByDefault = true;
      gitWtZsh = true;
      ghExtensions = {
        apiGet = true;
        do = true;
        poi = true;
      };
      settings = {
        autocrlf = "input";
        defaultBranch = "main";
        editor = "code --wait";
        worktreeBase = ".worktrees";
      };
      ignoresLocalClaude = true;
    };
    files = {
      sshConfig = true;
      sshCommon = true;
      sshPrivateAbsent = true;
      sshConfigIncludesFragments = true;
      sshCommonHasGithub = true;
    };
    activation = {
      aws = {
        afterWriteBoundary = true;
        usesRun = true;
        reconcilesConfig = true;
      };
      trash = {
        afterWriteBoundary = true;
        usesRun = true;
        createsFreedesktopDirectories = true;
        restrictsPermissions = true;
      };
    };
    cloud.gcloud = {
      default = true;
      personal = true;
      tdu = true;
    };
    security.gpg = {
      cacheTtl = 43200;
      maxCacheTtl = 43200;
      sshSupport = true;
      sshKeys = [ "60DE257CE1919B3D6DCF4E6E239CD1FFE63B45FD" ];
      windowsPinentry = false;
    };
    packages = {
      ax = true;
      aws = true;
      awsLogin = true;
      curl = true;
      gcloud = true;
      gitWt = true;
      trash = true;
      common = true;
    };
  };

  mkExpected =
    {
      environment,
      homeDirectory,
      registryPath,
      system,
    }:
    commonExpected
    // {
      agents = commonExpected.agents // {
        environment = {
          inherit environment;
          source = registryPath;
          hcomAbsent = true;
        };
        hunkUsesPlatformRuntime = true;
      };
      identity = {
        inherit homeDirectory system;
        username = username;
        stateVersion = "24.11";
        releaseCheck = true;
      };
      registry = {
        fromId = "dotfiles";
        fromType = "indirect";
        path = registryPath;
        toType = "path";
      };
      security.gpg = commonExpected.security.gpg // {
        windowsPinentry = environment == "wsl";
      };
      platform = {
        gpgPinentry =
          {
            darwin = "pinentry-mac";
            linux = "pinentry-curses";
            wsl = null;
          }
          .${environment};
        ghqSystemd = environment != "darwin";
        ghqLaunchd = environment == "darwin";
        ghqSchedule = true;
        ghqDurability = true;
        trashSystemd = environment != "darwin";
        trashLaunchd = environment == "darwin";
        trashSchedule = true;
        trashDurability = true;
        wslAuthSockOverride = environment == "wsl";
      };
    };

  expected = {
    "${username}@linux-x86_64" = mkExpected {
      environment = "linux";
      homeDirectory = "/home/${username}";
      registryPath = canonicalLinux;
      system = "x86_64-linux";
    };
    "${username}@linux-aarch64" = mkExpected {
      environment = "linux";
      homeDirectory = "/home/${username}";
      registryPath = canonicalLinux;
      system = "aarch64-linux";
    };
    "${username}@wsl-x86_64" = mkExpected {
      environment = "wsl";
      homeDirectory = "/home/${username}";
      registryPath = canonicalLinux;
      system = "x86_64-linux";
    };
    "${username}@wsl-aarch64" = mkExpected {
      environment = "wsl";
      homeDirectory = "/home/${username}";
      registryPath = canonicalLinux;
      system = "aarch64-linux";
    };
    wsl = mkExpected {
      environment = "wsl";
      homeDirectory = "/home/${username}";
      registryPath = toString inputs.self.outPath;
      system = "x86_64-linux";
    };
    wsl-aarch64 = mkExpected {
      environment = "wsl";
      homeDirectory = "/home/${username}";
      registryPath = toString inputs.self.outPath;
      system = "aarch64-linux";
    };
    darwin = mkExpected {
      environment = "darwin";
      homeDirectory = "/Users/${username}";
      registryPath = canonicalDarwin;
      system = "aarch64-darwin";
    };
  };
  actual = lib.mapAttrs (_: entry: describe entry) entries;
in
assert lib.assertMsg (actual == expected) ''
  Home feature contract mismatch:
  expected ${builtins.toJSON expected}
  actual ${builtins.toJSON actual}
'';
pkgs.runCommand "home-feature-contract" { } ''touch "$out"''
