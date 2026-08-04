{
  den,
  features,
  inputs,
  ...
}:
let
  profileAssertion = import ./_lib/profile-assertion.nix;
  baseHomeModule =
    owner: cleanupOwner:
    { ... }:
    {
      assertions = [
        (profileAssertion {
          expected = "wsl";
          inherit owner;
        })
      ];
      dotfiles.platform = {
        inherit (owner.dotfiles) environment source;
        standalone = owner.dotfiles.standalone or false;
        windows = owner.dotfiles.windows;
        nhCleanupOwner = cleanupOwner;
      };
    };
in
{
  den.aspects.environments.wsl = {
    name = "dotfiles-wsl";
    includes = [
      den.aspects.environments.base
      den.aspects.environments.integrated-home-manager
      features.registries-host
      features.agent-hunk-wsl
      features.security-gpg-wsl
      features.source-control-ghq-sync-systemd
      features.trash-systemd
      features.platform-wsl
    ];

    nixos =
      { host, ... }:
      let
        overlayPlan = import ../../../nix/lib/mk-overlays.nix { inherit inputs; } host.system;
      in
      {
        assertions = [
          (profileAssertion {
            expected = "wsl";
            owner = host;
          })
        ];
        nixpkgs = {
          overlays = overlayPlan.overlays;
        };
      };

    homeManager =
      { host, ... }:
      baseHomeModule host "nixos";
  };

  den.aspects.environments.standalone-wsl = {
    name = "dotfiles-standalone-wsl";
    includes = [
      den.aspects.environments.base
      features.registries-home
      features.agent-hunk-wsl
      features.security-gpg-wsl
      features.source-control-ghq-sync-systemd
      features.trash-systemd
      features.platform-wsl
    ];
    homeManager =
      { home, ... }:
      let
        overlayPlan = import ../../../nix/lib/mk-overlays.nix { inherit inputs; } home.system;
      in
      {
        imports = [ (baseHomeModule home "switch-app") ];
        nixpkgs = {
          overlays = overlayPlan.overlays;
        };
      };
  };
}
