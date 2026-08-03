{
  description = "constantan's home-manager configuration";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      # nixConfig は直接の attrset を要求して import を含む let 式を受理しないため、
      # cache-settings.nix との乖離を cache-settings-tests で検知する。
      "https://cache.numtide.com"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    den.url = "github:denful/den/2040b61346a7215fd7b7f51d4a457544b6e597d0";

    flake-file.url = "github:denful/flake-file/v0.6.0";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs-lib";
    };

    import-tree.url = "github:vic/import-tree/v0.2.0";

    nixpkgs-lib.follows = "nixpkgs";

    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    bun2nix = {
      url = "github:nix-community/bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "supported-systems";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    # CLI と skill は同じ input を version authority として使う。
    ax = {
      url = "github:yusukebe/ax/v0.1.23";
      inputs.bun2nix.follows = "bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hunk = {
      url = "github:modem-dev/hunk";
      inputs.bun2nix.follows = "bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };

    supported-systems = {
      url = "path:./nix/systems";
      flake = false;
    };

    rustsec-advisory-db = {
      url = "github:RustSec/advisory-db";
      flake = false;
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
    };

    mozuku = {
      # nixpkgs を follows しない (意図的): mozuku-lsp は cabocha / crfpp の
      # C++ チェーンごと source build になり、どのバイナリキャッシュにも無い。
      # follows にすると nixpkgs 更新の度に再ビルドが走る (実測 3 drv) ため、
      # upstream の pin のままにして再ビルドを mozuku 更新時だけに抑える。
      url = "github:t3tra-dev/MoZuKu";
    };

    codex-plugin-cc = {
      url = "github:openai/codex-plugin-cc";
      flake = false;
    };

    # External skill sources (deployed by nix/modules/home/agent-skills/)
    ast-grep-skill = {
      url = "github:ast-grep/claude-skill";
      flake = false;
    };

    agent-browser-skill = {
      url = "github:vercel-labs/agent-browser/v0.31.1";
      flake = false;
    };

    agent-slack-skill = {
      url = "github:stablyai/agent-slack/v0.9.3";
      flake = false;
    };

    anthropic-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };

    drawio-skill = {
      url = "github:jgraph/drawio-mcp";
      flake = false;
    };

    # difit official agent skills (the CLI implementation is in nix/packages/difit).
    # バイナリ側の pin (nix/pins/difit.json) とは `nix run .#update-pins` が
    # この input ごと同期する。
    difit-src = {
      url = "github:yoshiko-pg/difit/v5.0.8";
      flake = false;
    };

    # hcom skill source (the CLI implementation is in nix/packages/hcom).
    # バイナリ側の pin (nix/pins/hcom.json) とは `nix run .#update-pins` が
    # この input ごと同期する。
    hcom-src = {
      url = "github:aannoo/hcom/v0.7.21";
      flake = false;
    };

    improve-skill = {
      url = "github:shadcn/improve";
      flake = false;
    };

    # Homebrew casks managed via Nix (macOS only)
    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      inputs.brew-api.follows = "brew-api";
      inputs.nix-darwin.follows = "darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };

  };

  outputs = inputs: import ./modules/_legacy/outputs.nix inputs;
}
