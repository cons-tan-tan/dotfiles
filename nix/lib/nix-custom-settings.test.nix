{
  lib,
  username,
}:
let
  nixCustomSettings = import ./nix-custom-settings.nix { inherit lib username; };
  expectedLines = [
    "extra-substituters = https://cache.numtide.com https://nix-community.cachix.org"
    "extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "extra-trusted-substituters = https://cache.numtide.com https://nix-community.cachix.org"
    "extra-trusted-users = ${username}"
    "max-free = 68719476736"
    "min-free = 34359738368"
  ];
  actualLines = lib.filter (line: line != "") (lib.splitString "\n" nixCustomSettings.text);
in
{
  testRenderedLines = {
    expr = actualLines;
    expected = expectedLines;
  };
}
