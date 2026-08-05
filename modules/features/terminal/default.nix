{ features, ... }:
{
  features.terminal-default = {
    name = "feature/terminal/default";
    includes = [
      features.terminal-fastfetch
      features.terminal-yazi
    ];
  };
}
