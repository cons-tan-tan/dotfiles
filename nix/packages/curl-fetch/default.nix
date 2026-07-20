{
  curl,
  writeShellApplication,
}:
writeShellApplication {
  name = "curl-fetch";
  runtimeInputs = [ curl ];
  text = builtins.readFile ./curl-fetch.sh;
}
