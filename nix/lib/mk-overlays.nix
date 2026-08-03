{ inputs }:
system:
let
  inherit (inputs.nixpkgs) lib;
  common = [
    {
      name = "mozuku-lsp";
      value = import ../overlays/mozuku-lsp.nix { inherit inputs; };
    }
    {
      name = "llm-agents";
      value = import ../overlays/llm-agents.nix inputs.llm-agents;
    }
    {
      name = "local-packages";
      value = import ../overlays/local-packages.nix { inherit inputs; };
    }
  ];
  darwin = [
    {
      name = "watchexec";
      value = import ../overlays/watchexec.nix { };
    }
    {
      name = "brew-nix";
      value = inputs.brew-nix.overlays.default;
    }
  ];
  entries = common ++ lib.optionals (lib.hasSuffix "-darwin" system) darwin;
in
{
  names = map (entry: entry.name) entries;
  overlays = map (entry: entry.value) entries;
}
