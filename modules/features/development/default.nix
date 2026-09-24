{ config, ... }:
{
  flake.modules.homeManager.development-default = {
    key = "modules/features/development/default.nix#homeManager.development-default";
    imports = [
      config.flake.modules.homeManager.development-go
      config.flake.modules.homeManager.development-javascript
      config.flake.modules.homeManager.development-mozuku
      config.flake.modules.homeManager.development-python
      config.flake.modules.homeManager.development-rust
      config.flake.modules.homeManager.development-watchexec
    ];
  };
}
