{ ciCheck, pkgs }:
let
  ghSafeFetchArtifact = import ../../source-control/gh/_tests/safe-fetch-artifact.nix {
    inherit pkgs;
  };
in
[
  (import ../../platform/nix-settings/_tests/rust-project.nix { inherit ciCheck pkgs; })
  (import ../../security/secrets/_tests/rust-project.nix { inherit ciCheck pkgs; })
  (import ../../update-pins/_tests/rust-project.nix { inherit ciCheck pkgs; })
]
++ import ../../agents/base/_tests/rust-projects.nix { inherit ciCheck pkgs; }
++ [
  (import ../../cloud/aws/_tests/rust-project.nix { inherit ciCheck pkgs; })
  (import ../../network/curl/_tests/rust-project.nix {
    inherit ciCheck pkgs;
    publicArtifacts = [ ghSafeFetchArtifact ];
  })
  (import ../../platform/darwin/sleepctl/_tests/rust-project.nix { inherit ciCheck pkgs; })
]
