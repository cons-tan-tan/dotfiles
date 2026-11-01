{ pkgs }:
{
  nativeBuildInputs = [
    pkgs.gitMinimal
    pkgs.jq
    pkgs.python3
    pkgs.yq-go
  ];
  environment = { };
  requiredEnvironment = [ ];
}
