{
  flake.modules.darwin.input-methods-azookey = {
    key = "modules/features/input-methods/azookey.nix#darwin.input-methods-azookey";
    homebrew.casks = [ "azookey" ];
  };
}
