{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs_24,
}:

buildNpmPackage rec {
  pname = "difit";
  version = "5.0.4";

  src = fetchurl {
    url = "https://registry.npmjs.org/difit/-/difit-${version}.tgz";
    hash = "sha256-7bp/jajRzI2cUlHYWlrAz9KyK/ena0O3PAWS0bZ0Iqw=";
  };

  nodejs = nodejs_24;
  npmDepsHash = "sha256-irIWtQ6DoR20ZrvtgrnH3sHAvVH4Pxe2HlxrVVuseww=";
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
