{ lib }:
let
  settings = (import ./claude.nix { inherit lib; }).mkSettings { };
in
{
  testReadOnlyFetchWrappersStayAutoApproved = {
    expr = builtins.filter (
      permission:
      builtins.elem permission [
        "Bash(gh api-get *)"
        "Bash(curl-fetch *)"
      ]
    ) settings.permissions.allow;
    expected = [
      "Bash(gh api-get *)"
      "Bash(curl-fetch *)"
    ];
  };

  testRawCurlIsNotAutoApproved = {
    expr = builtins.elem "Bash(curl *)" settings.permissions.allow;
    expected = false;
  };
}
