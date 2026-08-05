{
  lib,
  pkgs,
  publicApps,
  repoRoot,
  subjects,
  username,
  cacheSettings,
  ciCheck,
}:
{
  standalone = [
    {
      fixture = import ../../../update-pins/_tests/bats-fixture.nix {
        inherit lib pkgs subjects;
      };
      shard = import ../../../update-pins/_tests/bats-shard.nix { inherit lib; };
    }
    {
      fixture = import ../../../ci/_tests/bats-fixture.nix {
        inherit cacheSettings pkgs;
      };
      shard = import ../../../ci/_tests/bats-shard.nix {
        inherit ciCheck lib repoRoot;
      };
    }
  ];

  safeFetch = [
    (import ../../../network/curl/_tests/bats-fragment.nix {
      inherit lib pkgs subjects;
    })
    (import ../../../source-control/gh/_tests/bats-fragment.nix {
      inherit lib pkgs subjects;
    })
  ];

  rustCli = [
    {
      fixture = import ../../../platform/nix-settings/_tests/bats-fixture.nix {
        inherit lib publicApps subjects;
      };
      shard = import ../../../platform/nix-settings/_tests/bats-shard.nix;
    }
    {
      fixture = import ../../../security/secrets/_tests/bats-fixture.nix {
        inherit lib publicApps subjects;
      };
      shard = import ../../../security/secrets/_tests/bats-shard.nix;
    }
  ];

  shellWrappers = [
    {
      fixture = import ../../../apps/host/_tests/bats-fixture.nix {
        inherit lib pkgs publicApps;
      };
      shard = import ../../../apps/host/_tests/bats-shard.nix;
    }
    (import ../../../agents/claude/_tests/bats-fragment.nix { inherit pkgs; })
    (import ../../../agents/codex/_tests/bats-fragment.nix { inherit pkgs; })
    (import ../../../agents/herdr/_tests/bats-fragment.nix { inherit lib pkgs; })
    (import ../../../agents/pi/_tests/bats-fragment.nix { inherit pkgs; })
    (import ../../../cloud/aws/_tests/bats-fragment.nix { inherit pkgs subjects; })
    (import ../../../platform/linux/drawio-headless/_tests/bats-fragment.nix {
      inherit lib pkgs;
    })
    (import ../../../platform/nh/_tests/bats-fragment.nix {
      inherit lib pkgs username;
    })
    (import ../../../platform/wsl-open/_tests/bats-fragment.nix { inherit lib pkgs; })
    (import ../../../security/gpg/_tests/bats-fragment.nix)
    (import ../../../source-control/ghq-sync/_tests/bats-fragment.nix { inherit pkgs; })
    (import ../../../windows/_tests/bats-fragment.nix { inherit lib pkgs; })
  ];
}
