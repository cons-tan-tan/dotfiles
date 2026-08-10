{ pkgs }:
{
  nativeBuildInputs = [
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnutar
    pkgs.gzip
    pkgs.jq
    pkgs.nodejs_24
    pkgs.openssl
  ];
  environment = { };
  requiredEnvironment = [ ];
}
