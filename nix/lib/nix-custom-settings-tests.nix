{
  lib,
  username,
}:
let
  nixCustomSettings = import ./nix-custom-settings.nix { inherit lib username; };
  expectedLines = [
    "extra-substituters = https://cache.numtide.com"
    "extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    "extra-trusted-substituters = https://cache.numtide.com"
    "extra-trusted-users = ${username}"
  ];
  actualLines = lib.filter (line: line != "") (lib.splitString "\n" nixCustomSettings.text);
in
lib.optionals (actualLines != expectedLines) [
  {
    test = "nix-custom-settings rendered lines";
    expected = expectedLines;
    actual = actualLines;
  }
]
