{
  contract,
  pkgs,
  runnerFactory,
}:
let
  inherit (pkgs) lib;
  nodeManifest = builtins.fromJSON (builtins.readFile (contract.nodeDir + "/package.json"));
  nodeLock = builtins.fromJSON (builtins.readFile (contract.nodeDir + "/package-lock.json"));
  pythonManifest = fromTOML (builtins.readFile (contract.pythonDir + "/pyproject.toml"));
  pythonLock = fromTOML (builtins.readFile (contract.pythonDir + "/uv.lock"));
  pythonRoots = builtins.filter (
    package: package.name == pythonManifest.project.name && (package.source.virtual or null) == "."
  ) pythonLock.package;
  pythonRoot = if builtins.length pythonRoots == 1 then builtins.head pythonRoots else { };
  dependencyContract =
    dependency:
    let
      parts = lib.splitString "[" dependency;
    in
    {
      name = lib.toLower (builtins.head parts);
      extras =
        if builtins.length parts == 1 then
          [ ]
        else
          lib.splitString "," (lib.removeSuffix "]" (builtins.elemAt parts 1));
    };
  projectDependencies = map dependencyContract pythonManifest.project.dependencies;
  lockedDependencies = map (dependency: {
    inherit (dependency) name;
    extras = dependency.extras or [ ];
  }) (pythonRoot.metadata.requires-dist or [ ]);
  structuralContract =
    nodeManifest.name == contract.nodeProjectName
    && nodeLock.packages."".name == contract.nodeProjectName
    && nodeManifest.dependencies == nodeLock.packages."".dependencies
    && pythonManifest.project.name == contract.pythonProjectName
    && builtins.length pythonRoots == 1
    && projectDependencies == lockedDependencies;

  fakeTool = pkgs.writeShellApplication {
    name = "pptx-validation-probe";
    text = ''
      : "''${PPTX_VALIDATION_ARGS_FILE:?}"
      : "''${PPTX_VALIDATION_PATH_FILE:?}"
      printf '%s\0' "$@" > "$PPTX_VALIDATION_ARGS_FILE"
      printf '%s' "$PATH" > "$PPTX_VALIDATION_PATH_FILE"
    '';
  };
  fakeTools = pkgs.runCommand "pptx-validation-tools" { } ''
    mkdir -p "$out/bin"
    ln -s '${lib.getExe fakeTool}' "$out/bin/pptx-validation-probe"
  '';
  runner = runnerFactory { toolPath = fakeTools; };
  allowedDependencyContext = builtins.getContext "${fakeTools}";
in
assert structuralContract;
assert runner.dependencyContext == allowedDependencyContext;
pkgs.runCommand "pptx-app-validation"
  {
    nativeBuildInputs = [ runner.package ];
  }
  ''
    if pptx-run > "$TMPDIR/no-args.stdout" 2> "$TMPDIR/no-args.stderr"; then
      echo "pptx accepted an empty invocation" >&2
      exit 1
    else
      status=$?
    fi
    test "$status" -eq 64
    test ! -s "$TMPDIR/no-args.stdout"
    grep -Fx 'usage: nix run dotfiles#pptx -- <command> [args...]' "$TMPDIR/no-args.stderr"

    export PPTX_VALIDATION_ARGS_FILE="$TMPDIR/args"
    export PPTX_VALIDATION_PATH_FILE="$TMPDIR/path"
    pptx-run pptx-validation-probe 'argument with spaces' tail
    printf '%s\0' 'argument with spaces' tail > "$TMPDIR/expected-args"
    cmp "$TMPDIR/expected-args" "$PPTX_VALIDATION_ARGS_FILE"
    case "$(cat "$PPTX_VALIDATION_PATH_FILE")" in
      '${fakeTools}/bin:'*) ;;
      *)
        echo "pptx runner did not prepend the injected tool path" >&2
        exit 1
        ;;
    esac

    touch "$out"
  ''
