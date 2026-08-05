{ pkgs }:
{ toolPath }:
let
  text = ''
    # Direct interpolation keeps the injected tool environment in the runtime
    # closure. The value is a store path and safe to quote.
    export PPTX_RUN_TOOL_PATH="${toolPath}"
    ${builtins.readFile ./runner.sh}
  '';
in
{
  dependencyContext = builtins.getContext text;
  package = pkgs.writeShellApplication {
    name = "pptx-run";
    inherit text;
  };
}
