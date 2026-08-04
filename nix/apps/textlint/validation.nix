{
  contract,
  pkgs,
  runnerFactory,
}:
let
  inherit (pkgs) lib;
  manifest = builtins.fromJSON (builtins.readFile (contract.nodeDir + "/package.json"));
  lock = builtins.fromJSON (builtins.readFile (contract.nodeDir + "/package-lock.json"));
  lockRoot = lock.packages."";
  lockedPackage = lock.packages."node_modules/${contract.packageName}";
  modeConfigs = map (mode: mode.config) (builtins.attrValues contract.modes);
  structuralContract =
    manifest.dependencies == lockRoot.dependencies
    && builtins.hasAttr contract.packageName manifest.dependencies
    && (lockedPackage.bin.${contract.binName} or null) == contract.entry
    && builtins.all builtins.pathExists modeConfigs;

  fakeLint = pkgs.writeShellApplication {
    name = "textlint-validation-probe";
    text = ''
      : "''${TEXTLINT_VALIDATION_ARGS_FILE:?}"
      printf '%s\0' "$@" > "$TEXTLINT_VALIDATION_ARGS_FILE"
    '';
  };
  runner = runnerFactory {
    inherit (contract) modes;
    lintExecutable = lib.getExe fakeLint;
  };
  allowedDependencyContext = builtins.getContext (
    lib.concatStringsSep " " ([ (lib.getExe fakeLint) ] ++ map (config: "${config}") modeConfigs)
  );
in
assert structuralContract;
assert runner.dependencyContext == allowedDependencyContext;
pkgs.runCommand "textlint-app-validation"
  {
    nativeBuildInputs = [ runner.package ];
  }
  ''
    if textlint-run > "$TMPDIR/no-args.stdout" 2> "$TMPDIR/no-args.stderr"; then
      echo "textlint accepted an empty invocation" >&2
      exit 1
    else
      status=$?
    fi
    test "$status" -eq 64
    test ! -s "$TMPDIR/no-args.stdout"
    grep -Fx 'usage: nix run dotfiles#textlint -- tech-jp <files...>' "$TMPDIR/no-args.stderr"

    textlint-run --help > "$TMPDIR/help.stdout" 2> "$TMPDIR/help.stderr"
    test ! -s "$TMPDIR/help.stdout"
    grep -Fx 'usage: nix run dotfiles#textlint -- tech-jp <files...>' "$TMPDIR/help.stderr"

    if textlint-run unknown file.md > "$TMPDIR/unknown.stdout" 2> "$TMPDIR/unknown.stderr"; then
      echo "textlint accepted an unknown mode" >&2
      exit 1
    else
      status=$?
    fi
    test "$status" -eq 64
    grep -Fx 'textlint: unknown mode: unknown' "$TMPDIR/unknown.stderr"

    if textlint-run tech-jp > "$TMPDIR/no-files.stdout" 2> "$TMPDIR/no-files.stderr"; then
      echo "textlint accepted a mode without files" >&2
      exit 1
    else
      status=$?
    fi
    test "$status" -eq 64

    export TEXTLINT_VALIDATION_ARGS_FILE="$TMPDIR/args"
    textlint-run tech-jp 'docs/file with spaces.md'
    printf '%s\0' \
      --config \
      '${contract.modes.tech-jp.config}' \
      'docs/file with spaces.md' > "$TMPDIR/expected-args"
    cmp "$TMPDIR/expected-args" "$TEXTLINT_VALIDATION_ARGS_FILE"

    touch "$out"
  ''
