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
  structuralContract =
    manifest.dependencies == lockRoot.dependencies
    && builtins.hasAttr contract.packageName manifest.dependencies
    && (lockedPackage.bin.${contract.binName} or null) == contract.entry
    && builtins.pathExists contract.config;

  fakeLint = pkgs.writeShellApplication {
    name = "markdownlint-validation-probe";
    text = ''
      : "''${MARKDOWNLINT_VALIDATION_ARGS_FILE:?}"
      printf '%s\0' "$@" > "$MARKDOWNLINT_VALIDATION_ARGS_FILE"
    '';
  };
  runner = runnerFactory {
    inherit (contract) config;
    lintExecutable = lib.getExe fakeLint;
  };
  allowedDependencyContext = builtins.getContext "${lib.getExe fakeLint} ${contract.config}";
in
assert structuralContract;
assert runner.dependencyContext == allowedDependencyContext;
pkgs.runCommand "markdownlint-app-validation"
  {
    nativeBuildInputs = [ runner.package ];
  }
  ''
    if markdownlint-run > "$TMPDIR/no-args.stdout" 2> "$TMPDIR/no-args.stderr"; then
      echo "markdownlint accepted an empty invocation" >&2
      exit 1
    else
      status=$?
    fi
    test "$status" -eq 64
    test ! -s "$TMPDIR/no-args.stdout"
    grep -Fx 'usage: nix run dotfiles#markdownlint -- <files...>' "$TMPDIR/no-args.stderr"

    markdownlint-run --help > "$TMPDIR/help.stdout" 2> "$TMPDIR/help.stderr"
    test ! -s "$TMPDIR/help.stdout"
    grep -Fx 'usage: nix run dotfiles#markdownlint -- <files...>' "$TMPDIR/help.stderr"

    export MARKDOWNLINT_VALIDATION_ARGS_FILE="$TMPDIR/args"
    markdownlint-run 'docs/file with spaces.md'
    printf '%s\0' \
      --config \
      '${contract.config}' \
      'docs/file with spaces.md' > "$TMPDIR/expected-args"
    cmp "$TMPDIR/expected-args" "$MARKDOWNLINT_VALIDATION_ARGS_FILE"

    touch "$out"
  ''
