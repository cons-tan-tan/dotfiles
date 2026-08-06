{ pkgs }:
{
  nativeBuildInputs = [
    pkgs.check-jsonschema
    pkgs.gitMinimal
    pkgs.jq
    pkgs.python3
    pkgs.yq-go
  ];
  environment = { };
  requiredEnvironment = [ ];
}
