{ homeConfiguration }:
(homeConfiguration.extendModules {
  modules = [ { dotfiles.hcom.enable = true; } ];
}).activationPackage
