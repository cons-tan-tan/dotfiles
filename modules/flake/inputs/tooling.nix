{
  flake-file.inputs = {
    ax = {
      # CLI と skill は同じ input を version authority として使う。
      url = "github:yusukebe/ax/v0.1.23";
      inputs.bun2nix.follows = "bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    bun2nix = {
      url = "github:nix-community/bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "supported-systems";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    hunk = {
      url = "github:modem-dev/hunk";
      inputs.bun2nix.follows = "bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents.url = "github:numtide/llm-agents.nix";
  };
}
