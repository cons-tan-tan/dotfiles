{ pkgs }:
{
  config,
  lintExecutable,
}:
let
  text = ''
    # Direct interpolation keeps Nix path context so both dependencies enter
    # the runtime closure. These values are store paths and safe to quote.
    export MARKDOWNLINT_RUN_LINT="${lintExecutable}"
    export MARKDOWNLINT_RUN_CONFIG="${config}"
    ${builtins.readFile ./runner.sh}
  '';
in
{
  dependencyContext = builtins.getContext text;
  package = pkgs.writeShellApplication {
    name = "markdownlint-run";
    inherit text;
  };
}
