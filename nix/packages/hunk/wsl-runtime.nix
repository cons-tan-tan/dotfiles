{
  bun,
  lib,
  makeWrapper,
  package,
}:
# Bun の compile 済み単一バイナリは WSL2 で起動直後に segfault するため、
# WSL だけ同じ固定ソースと依存を Bun ランタイムで直接起動する。
package.overrideAttrs (oldAttrs: {
  nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ makeWrapper ];

  buildPhase = ''
    runHook preBuild
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/lib/hunk"
    cp -r node_modules packages skills src package.json "$out/lib/hunk/"
    makeWrapper ${lib.getExe bun} "$out/bin/hunk" \
      --add-flags "$out/lib/hunk/src/main.tsx"
    ln -s "$out/lib/hunk/skills" "$out/skills"
    runHook postInstall
  '';
})
