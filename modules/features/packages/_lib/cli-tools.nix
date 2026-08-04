# Windows companion packages and their corresponding Linux installation route.
[
  {
    winget = {
      id = "git";
      packageId = "Git.Git";
      elevated = true;
      description = "Git for Windows";
    };
    linux = "programs";
  }
  {
    winget = {
      id = "gpg4win";
      packageId = "GnuPG.Gpg4win";
      elevated = true;
      description = "Gpg4win";
    };
    linux = "none";
  }
  {
    winget = {
      id = "op-cli";
      packageId = "AgileBits.1Password.CLI";
      description = "1Password CLI";
    };
    linux = "none";
  }
  {
    winget = {
      id = "claude-code";
      packageId = "Anthropic.ClaudeCode";
      description = "Claude Code CLI";
    };
    linux = "dotfiles-package";
  }
  {
    winget = {
      id = "rg";
      packageId = "BurntSushi.ripgrep.MSVC";
      description = "ripgrep";
    };
    linux = "home-packages";
    nixpkgsAttr = "ripgrep";
  }
  {
    winget = {
      id = "fd";
      packageId = "sharkdp.fd";
      description = "fd";
    };
    linux = "home-packages";
    nixpkgsAttr = "fd";
  }
  {
    winget = {
      id = "bat";
      packageId = "sharkdp.bat";
      description = "bat";
    };
    linux = "home-packages";
    nixpkgsAttr = "bat";
  }
  {
    winget = {
      id = "eza";
      packageId = "eza-community.eza";
      description = "eza";
    };
    linux = "home-packages";
    nixpkgsAttr = "eza";
  }
  {
    winget = {
      id = "jq";
      packageId = "jqlang.jq";
      description = "jq";
    };
    linux = "home-packages";
    nixpkgsAttr = "jq";
  }
  {
    winget = {
      id = "ast-grep";
      packageId = "ast-grep.ast-grep";
      description = "ast-grep";
    };
    linux = "home-packages";
    nixpkgsAttr = "ast-grep";
  }
  {
    winget = {
      id = "fzf";
      packageId = "junegunn.fzf";
      description = "fzf";
    };
    linux = "home-packages";
    nixpkgsAttr = "fzf";
  }
  {
    winget = {
      id = "gh";
      packageId = "GitHub.cli";
      dependsOn = [ "git" ];
      description = "GitHub CLI";
    };
    linux = "programs";
  }
  {
    winget = {
      id = "ghq";
      packageId = "x-motemen.ghq";
      dependsOn = [ "git" ];
      description = "ghq";
    };
    linux = "home-packages";
    nixpkgsAttr = "ghq";
  }
  {
    winget = {
      id = "starship";
      packageId = "Starship.Starship";
      description = "Starship";
    };
    linux = "programs";
  }
  {
    winget = {
      id = "zoxide";
      packageId = "ajeetdsouza.zoxide";
      description = "zoxide";
    };
    linux = "programs";
  }
  {
    winget = {
      id = "zed";
      packageId = "ZedIndustries.Zed";
      description = "Zed";
    };
    linux = "none";
  }
  {
    winget = {
      id = "wt";
      packageId = "Microsoft.WindowsTerminal";
      description = "Windows Terminal";
    };
    linux = "none";
  }
  {
    winget = {
      id = "pwsh";
      packageId = "Microsoft.PowerShell";
      description = "PowerShell 7";
    };
    linux = "none";
  }
]
