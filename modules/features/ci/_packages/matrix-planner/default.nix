{
  lib,
  or-tools,
  python313,
  python313Packages,
  writeShellApplication,
}:
let
  # CP-SAT does not use SCIP.  The pinned nixpkgs OR-Tools check still imports
  # pkg_resources, which setuptools 83 removed, so keep setuptools 80 only in
  # the upstream build/test environment.
  orTools =
    (or-tools.override {
      python3 = python313;
      withScip = false;
    }).overrideAttrs
      (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ python313Packages.setuptools_80 ];
      });
  ortools = python313Packages.ortools.override { or-tools = orTools; };
  python = python313.withPackages (_: [ ortools ]);
in
writeShellApplication {
  name = "plan-ci-matrix";
  runtimeInputs = [ python ];
  text = ''
    exec ${python}/bin/python3 ${../../_scripts}/plan_ci_matrix.py "$@"
  '';
  passthru = { inherit python; };
  meta = {
    description = "Plan the dotfiles Hestia matrix from CI telemetry";
    license = lib.licenses.cc0;
    platforms = lib.platforms.linux;
    mainProgram = "plan-ci-matrix";
  };
}
