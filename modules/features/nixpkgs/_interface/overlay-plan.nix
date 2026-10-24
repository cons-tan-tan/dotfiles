{
  inputs,
  llmAgentsOverlay,
  localPackageRegistry,
  mozukuOverlay,
  watchexecOverlay,
}:
system:
let
  inherit (inputs.nixpkgs) lib;
  common = [
    {
      name = "mozuku-lsp";
      value = mozukuOverlay { inherit inputs; };
    }
    {
      name = "llm-agents";
      value = llmAgentsOverlay inputs.llm-agents;
    }
    {
      name = "emudhra";
      value = import ../_overlays/emudhra.nix;
    }
    {
      name = "package-compatibility";
      value = import ../_overlays/compatibility.nix;
    }
    {
      name = "local-packages";
      value = import ../_overlays/local-packages.nix {
        inherit inputs;
        registry = localPackageRegistry;
      };
    }
    {
      name = "watchexec";
      value = watchexecOverlay;
    }
  ];
  darwin = [
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
