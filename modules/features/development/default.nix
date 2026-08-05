{ features, ... }:
{
  features.development-default = {
    name = "feature/development/default";
    includes = [
      features.development-go
      features.development-javascript
      features.development-mozuku
      features.development-nix
      features.development-python
      features.development-rust
      features.development-watchexec
    ];
  };
}
