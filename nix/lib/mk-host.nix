{
  inputs,
  username,
  homedir,
}:
{
  hostKind,
  system,
  hostFile,
}:
let
  pkgs = (import ./mk-pkgs.nix { inherit inputs; }) system;
in
inputs.home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  extraSpecialArgs = {
    inherit hostKind;
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
  modules = [
    inputs.agent-skills.homeManagerModules.default
    hostFile
    {
      home = {
        inherit username;
        homeDirectory = homedir;
      };
    }
  ];
}
