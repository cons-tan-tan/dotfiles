{
  flake-file.inputs = {
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
