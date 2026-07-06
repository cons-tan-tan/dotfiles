{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs_24,
  difitPin ? builtins.fromJSON (builtins.readFile ../../pins/difit.json),
}:
let
  # version / hash は nix/pins/difit.json に固定し、`nix run .#update-pins` で
  # 自動更新する (flake input difit-src も同時に更新される)。
  pin = difitPin;
  inherit (pin) version;
in
buildNpmPackage {
  pname = "difit";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/difit/-/difit-${version}.tgz";
    hash = pin.srcHash;
  };

  nodejs = nodejs_24;
  npmDepsHash = pin.npmDepsHash;
  npmInstallFlags = [ "--omit=dev" ];
  npmPackFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  meta = {
    description = "GitHub-style local Git diff viewer for code review";
    homepage = "https://github.com/yoshiko-pg/difit";
    license = lib.licenses.mit;
    mainProgram = "difit";
    platforms = nodejs_24.meta.platforms;
  };
}
