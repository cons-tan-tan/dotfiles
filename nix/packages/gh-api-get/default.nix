{
  gh,
  symlinkJoin,
  writeShellApplication,
}:
let
  binary = writeShellApplication {
    name = "gh-api-get";
    runtimeInputs = [ gh ];
    text = builtins.readFile ./gh-api-get.sh;
  };
in
# gh extension lookup expects the executable at the extension root, while
# writeShellApplication installs it under bin/.
symlinkJoin {
  name = "gh-api-get";
  paths = [ binary ];
  postBuild = ''
    ln -s "$out/bin/gh-api-get" "$out/gh-api-get"
  '';
}
// {
  # Home Manager names gh extension directories from pname.
  pname = "gh-api-get";
}
