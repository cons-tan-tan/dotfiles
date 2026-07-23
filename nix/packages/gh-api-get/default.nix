{
  gh,
  lib,
  makeWrapper,
  runCommand,
  safeFetchCore,
}:
runCommand "gh-api-get"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta = {
      description = "Read-only GitHub API wrapper with a positive argument policy";
      license = lib.licenses.cc0;
      mainProgram = "gh-api-get";
    };
  }
  ''
    mkdir -p "$out/bin"
    makeWrapper "${safeFetchCore}/bin/gh-api-get" "$out/bin/gh-api-get" \
      --set SAFE_FETCH_GH_BIN "${lib.getExe gh}"

    # gh extension lookup expects the executable at the extension root.
    ln -s "$out/bin/gh-api-get" "$out/gh-api-get"
  ''
// {
  # Home Manager names gh extension directories from pname.
  pname = "gh-api-get";
}
