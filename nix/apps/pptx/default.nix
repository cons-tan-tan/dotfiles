{
  anthropic-skills,
  pkgs,
  pyproject-build-systems,
  pyproject-nix,
  uv2nix,
}:

let
  pptxSkillDir = "${anthropic-skills}/skills/pptx";

  pythonWorkspace = uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = ./python;
  };

  pythonSet =
    (pkgs.callPackage pyproject-nix.build.packages {
      python = pkgs.python3;
    }).overrideScope
      (
        pkgs.lib.composeManyExtensions [
          pyproject-build-systems.overlays.default
          (pythonWorkspace.mkPyprojectOverlay {
            sourcePreference = "wheel";
          })
        ]
      );

  pythonEnv = pythonSet.mkVirtualEnv "pptx-python-env" pythonWorkspace.deps.default;

  pythonWrapper = pkgs.runCommandLocal "pptx-python-wrapper" { } ''
    mkdir -p "$out/bin"

    cat > "$out/bin/python" <<'EOF'
    #!${pkgs.runtimeShell}
    if [ "$#" -gt 0 ]; then
      script="$1"
      case "$script" in
        scripts/*)
          if [ ! -e "$script" ]; then
            shift
            exec "${pythonEnv}/bin/python" "${pptxSkillDir}/$script" "$@"
          fi
          ;;
      esac
    fi

    exec "${pythonEnv}/bin/python" "$@"
    EOF

    chmod +x "$out/bin/python"
    ln -s python "$out/bin/python3"
  '';

  pptxNodePackage = pkgs.lib.importJSON ./node/package.json;

  pptxNodeModules = pkgs.importNpmLock.buildNodeModules {
    package = pptxNodePackage;
    packageLock = pkgs.lib.importJSON ./node/package-lock.json;
    inherit (pkgs) nodejs;
    derivationArgs = {
      pname = "pptx-node-modules";
      version = pptxNodePackage.version;
    };
  };

  nodeWrapper = pkgs.runCommandLocal "pptx-node-wrapper" { } ''
    mkdir -p "$out/bin"

    cat > "$out/bin/node" <<'EOF'
    #!${pkgs.runtimeShell}
    export NODE_PATH="${pptxNodeModules}/node_modules''${NODE_PATH:+:$NODE_PATH}"
    exec ${pkgs.nodejs}/bin/node "$@"
    EOF

    chmod +x "$out/bin/node"

    for bin in npm npx corepack; do
      if [ -x "${pkgs.nodejs}/bin/$bin" ]; then
        ln -s "${pkgs.nodejs}/bin/$bin" "$out/bin/$bin"
      fi
    done
  '';

  sofficeDarwin = pkgs.writeShellApplication {
    name = "soffice";
    runtimeInputs = [ pkgs.libreoffice-bin ];
    text = ''
      exec "${pkgs.libreoffice-bin}/Applications/LibreOffice.app/Contents/MacOS/soffice" "$@"
    '';
  };

  pptxTools = pkgs.buildEnv {
    name = "pptx-tools";
    paths =
      with pkgs;
      [
        nodeWrapper
        pnpm
        poppler-utils
        pythonWrapper
      ]
      ++ lib.optionals stdenv.isLinux [
        gcc
        libreoffice
      ]
      ++ lib.optionals stdenv.isDarwin [
        sofficeDarwin
      ];
  };

  runner = pkgs.writeShellApplication {
    name = "pptx-run";
    text = ''
      if [ "$#" -eq 0 ]; then
        echo "usage: nix run dotfiles#pptx -- <command> [args...]" >&2
        exit 64
      fi

      export PATH="${pptxTools}/bin:$PATH"
      exec "$@"
    '';
  };
in
{
  type = "app";
  meta.description = "Run commands in the repository-managed PPTX conversion toolchain";
  program = pkgs.lib.getExe runner;
}
