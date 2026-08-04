{ lib }:
let
  validate = import ./validate-flake-unfree-packages.nix { inherit lib; };
in
{
  testValidNamesAreDeduplicated = {
    expr = validate [
      "codex-app"
      "raycast"
      "codex-app"
    ];
    expected = [
      "codex-app"
      "raycast"
    ];
  };

  testNonListPayloadIsRejected = {
    expr = (builtins.tryEval (validate "codex-app")).success;
    expected = false;
  };

  testEmptyNameIsRejected = {
    expr = (builtins.tryEval (builtins.deepSeq (validate [ "" ]) null)).success;
    expected = false;
  };

  testInvalidNameIsRejected = {
    expr = (builtins.tryEval (builtins.deepSeq (validate [ "codex app" ]) null)).success;
    expected = false;
  };
}
