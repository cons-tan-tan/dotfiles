{ features, ... }:
{
  features.editors-default = {
    name = "feature/editors/default";
    includes = [
      features.editors-neovim
      features.editors-zed
    ];
  };
}
