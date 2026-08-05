{ pkgs }:
{
  lintExecutable,
  modes,
}:
let
  modeNames = builtins.attrNames modes;
  text = ''
    # Direct interpolation keeps Nix path context so both dependencies enter
    # the runtime closure. These values are store paths and safe to quote.
    export TEXTLINT_RUN_LINT="${lintExecutable}"
    export TEXTLINT_RUN_TECH_JP_CONFIG="${modes.tech-jp.config}"
    ${builtins.readFile ./runner.sh}
  '';
in
assert modeNames == [ "tech-jp" ];
{
  dependencyContext = builtins.getContext text;
  package = pkgs.writeShellApplication {
    name = "textlint-run";
    inherit text;
  };
}
