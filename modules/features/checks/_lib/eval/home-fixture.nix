{
  inputs,
  lib,
  repoRoot,
}:
{
  files,
  modules,
  pkgs ? inputs.nixpkgs.legacyPackages.x86_64-linux,
}:
let
  registry =
    (lib.evalModules {
      specialArgs = {
        inherit inputs;
        moduleLocation = "home fixture";
      };
      modules = [
        inputs.flake-parts.flakeModules.modules
        {
          options.flake-file = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
        }
      ]
      ++ map (path: repoRoot + "/modules/features/${path}") files;
    }).config.flake.modules.homeManager;
in
inputs.home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  modules = [
    {
      home = {
        username = lib.mkDefault "test";
        homeDirectory = lib.mkDefault "/home/test";
        stateVersion = "25.11";
      };
    }
  ]
  ++ modules registry;
}
