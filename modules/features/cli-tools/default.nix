{ features, ... }:
{
  features.cli-tools-consumer = {
    name = "feature/cli-tools/consumer";
    homeManager =
      {
        cli-tools,
        lib,
        pkgs,
        ...
      }:
      let
        aggregated = import ./_lib/aggregate.nix { inherit lib pkgs; } cli-tools;
      in
      {
        home.packages = aggregated.nixHomePackages;
      };
  };

  features.cli-tools = {
    name = "feature/cli-tools";
    includes = [
      features.cli-tools-consumer
      features.cli-tool-reuse
      features.cli-tool-rg
      features.cli-tool-fd
      features.cli-tool-bat
      features.cli-tool-eza
      features.cli-tool-jq
      features.ast-grep
      features.cli-tool-fzf
    ];
  };
}
