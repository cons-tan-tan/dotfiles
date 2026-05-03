{
  pkgs,
  lib,
  hostKind,
  windowsHomedir,
  ...
}:
let
  hk = import ../../../lib/host-kind.nix { inherit hostKind; };

  yamlFormat = pkgs.formats.yaml { };

  mkWinGetPackage =
    {
      id,
      packageId,
      source ? "winget",
      dependsOn ? [ ],
      elevated ? false,
      description ? null,
    }:
    {
      resource = "Microsoft.WinGet.DSC/WinGetPackage";
      inherit id;
      directives =
        lib.optionalAttrs (description != null) { inherit description; }
        // lib.optionalAttrs elevated { securityContext = "elevated"; };
      settings = {
        id = packageId;
        inherit source;
      }
      // lib.optionalAttrs (source == "winget") {
        useLatest = true;
      };
    }
    // lib.optionalAttrs (dependsOn != [ ]) { inherit dependsOn; };

  packages = map mkWinGetPackage [
    {
      id = "git";
      packageId = "Git.Git";
      elevated = true;
      description = "Git for Windows";
    }
    {
      id = "gpg4win";
      packageId = "GnuPG.Gpg4win";
      elevated = true;
      description = "Gpg4win";
    }
    {
      id = "op-cli";
      packageId = "AgileBits.1Password.CLI";
      description = "1Password CLI";
    }
    {
      id = "claude-code";
      packageId = "Anthropic.ClaudeCode";
      description = "Claude Code CLI";
    }
    {
      id = "rg";
      packageId = "BurntSushi.ripgrep.MSVC";
      description = "ripgrep";
    }
    {
      id = "fd";
      packageId = "sharkdp.fd";
      description = "fd";
    }
    {
      id = "bat";
      packageId = "sharkdp.bat";
      description = "bat";
    }
    {
      id = "eza";
      packageId = "eza-community.eza";
      description = "eza";
    }
    {
      id = "jq";
      packageId = "jqlang.jq";
      description = "jq";
    }
    {
      id = "ast-grep";
      packageId = "ast-grep.ast-grep";
      description = "ast-grep";
    }
    {
      id = "fzf";
      packageId = "junegunn.fzf";
      description = "fzf";
    }
    {
      id = "gh";
      packageId = "GitHub.cli";
      dependsOn = [ "git" ];
      description = "GitHub CLI";
    }
    {
      id = "ghq";
      packageId = "x-motemen.ghq";
      dependsOn = [ "git" ];
      description = "ghq";
    }
    {
      id = "starship";
      packageId = "Starship.Starship";
      description = "Starship";
    }
    {
      id = "zoxide";
      packageId = "ajeetdsouza.zoxide";
      description = "zoxide";
    }
    {
      id = "wt";
      packageId = "Microsoft.WindowsTerminal";
      description = "Windows Terminal";
    }
    {
      id = "vscode";
      packageId = "Microsoft.VisualStudioCode";
      description = "Visual Studio Code";
    }
    {
      id = "pwsh";
      packageId = "Microsoft.PowerShell";
      description = "PowerShell 7";
    }
  ];

  wingetConfig = {
    properties = {
      assertions = [
        {
          resource = "Microsoft.Windows.Developer/OsVersion";
          directives = {
            description = "Win11 22H2 or later";
            allowPrerelease = true;
          };
          settings = {
            MinVersion = "10.0.22621";
          };
        }
      ];
      resources = packages;
      configurationVersion = "0.2.0";
    };
  };

  # pkgs.formats.yaml does not preserve top-level comments; prepend the
  # language-server schema directive so editors get completion.
  wingetConfigFile =
    pkgs.runCommand "dev.winget"
      {
        rawYaml = yamlFormat.generate "dev-raw.winget" wingetConfig;
      }
      ''
        {
          echo '# yaml-language-server: $schema=https://aka.ms/configuration-dsc-schema/0.2'
          cat $rawYaml
        } > $out
      '';
in
{
  home.activation = lib.mkIf hk.hasWindowsCompanion {
    deployWingetConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${windowsHomedir}/.config
      run install -m644 ${wingetConfigFile} ${windowsHomedir}/.config/dev.winget
    '';
  };
}
