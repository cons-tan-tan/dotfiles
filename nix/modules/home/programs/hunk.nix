{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  hunkPackage = pkgs.dotfilesPackages.hunk;

  # Bun の compile 済み単一バイナリは WSL2 で起動直後に segfault するため、
  # WSL だけ同じ固定ソースと依存を Bun ランタイムで直接起動する。
  hunkRuntimePackage = hunkPackage.overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];

    buildPhase = ''
      runHook preBuild
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/lib/hunk"
      cp -r node_modules packages skills src package.json "$out/lib/hunk/"
      makeWrapper ${lib.getExe pkgs.bun} "$out/bin/hunk" \
        --add-flags "$out/lib/hunk/src/main.tsx"
      ln -s "$out/lib/hunk/skills" "$out/skills"
      runHook postInstall
    '';
  });
in
{
  # Import the option module without upstream's default package, because the
  # local package supplies the bun2nix context fix.
  imports = [ inputs.hunk.homeManagerModules.hunk ];

  programs.hunk = {
    enable = true;
    enableGitIntegration = true;
    package = if config.my.hostKind == "wsl" then hunkRuntimePackage else hunkPackage;
    settings.wrap_lines = true;
  };
}
