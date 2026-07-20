{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs_24,
  difitSource,
  difitPin ? builtins.fromJSON (builtins.readFile ../../pins/difit.json),
}:
let
  # version は skill と共有する difit-src、配布物の hash は JSON pin が所有する。
  # `nix run .#update-pins` は両方を同じ transaction で更新する。
  pin = difitPin;
  version = (builtins.fromJSON (builtins.readFile "${difitSource}/package.json")).version;
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
