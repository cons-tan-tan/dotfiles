{
  inputs,
  username,
  homedir,
}:
{
  hostname,
  system,
  hostFile,
}:
let
  pkgs = (import ./mk-pkgs.nix { inherit inputs; }) system;
  hostKind = "darwin";
  windowsUsername = null;
  windowsHomedir = null;
in
inputs.nix-darwin.lib.darwinSystem {
  inherit system;
  specialArgs = {
    inherit
      username
      homedir
      hostname
      hostKind
      ;
  };
  modules = [
    { nixpkgs.pkgs = pkgs; }
    ../modules/darwin/system.nix

    inputs.home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = {
        inherit hostKind windowsUsername windowsHomedir;
        dotfilesDir = "${homedir}/ghq/github.com/cons-tan-tan/dotfiles";
        inherit (inputs)
          codex-plugin-cc
          ast-grep-skill
          agent-browser-skill
          agent-slack-skill
          anthropic-skills
          drawio-skill
          ;
      };
      home-manager.users.${username} = {
        imports = [
          inputs.agent-skills.homeManagerModules.default
          hostFile
        ];
        home = {
          inherit username;
          homeDirectory = homedir;
        };
      };
    }
  ];
}
