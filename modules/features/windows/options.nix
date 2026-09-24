{ lib, ... }:
let
  fileType = lib.types.submodule {
    options = {
      source = lib.mkOption { type = lib.types.str; };
      destination = lib.mkOption { type = lib.types.str; };
      mode = lib.mkOption {
        type = lib.types.strMatching "0[0-7]{3}";
        default = "0644";
      };
    };
  };
  treeType = lib.types.submodule {
    options = {
      source = lib.mkOption { type = lib.types.str; };
      destination = lib.mkOption { type = lib.types.str; };
      excludes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };
  resourceType = lib.types.submodule {
    options = {
      directories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      files = lib.mkOption {
        type = lib.types.listOf fileType;
        default = [ ];
      };
      trees = lib.mkOption {
        type = lib.types.listOf treeType;
        default = [ ];
      };
    };
  };
in
{
  flake.modules.homeManager.home-base = {
    key = "windows/options";
    options.dotfiles.windows = lib.mkOption {
      internal = true;
      default = { };
      description = "Resources and deployment state for the WSL-owned Windows companion.";
      type = lib.types.submodule {
        options = {
          wingetEnabled = lib.mkOption {
            type = lib.types.bool;
            default = false;
            internal = true;
          };
          deployments = lib.mkOption {
            type = lib.types.attrsOf resourceType;
            default = { };
          };
          staticResources = lib.mkOption {
            type = lib.types.attrsOf resourceType;
            default = { };
          };
        };
      };
    };
  };
}
