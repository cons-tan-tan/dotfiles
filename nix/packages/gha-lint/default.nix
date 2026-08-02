{
  bun2nix,
  fetchurl,
  lib,
  shellcheck,
  stdenv,
}:
let
  manifest = lib.importJSON ./package.json;
  schemaProvenance = lib.importJSON ./schema-provenance.json;
  schemaStoreRevision = "60cfa479d5901714547053ecee643a0a4c3a76fe";
  schemaStoreRaw = "https://raw.githubusercontent.com/SchemaStore/schemastore/${schemaStoreRevision}";
  workflowSchema = fetchurl {
    name = "github-workflow.json";
    url = "${schemaStoreRaw}/src/schemas/json/github-workflow.json";
    hash = "sha256-epUv23wbEwcy5AzOqdubztkGwRmOl4NPikmuO0EfMWE=";
  };
  actionSchema = fetchurl {
    name = "github-action.json";
    url = "${schemaStoreRaw}/src/schemas/json/github-action.json";
    hash = "sha256-g7078MQSLOt2SSe8GJ2eN5STEwa1PN+JgW9vNHLK34g=";
  };
  schemaStoreLicense = fetchurl {
    name = "SchemaStore-LICENSE";
    url = "${schemaStoreRaw}/LICENSE";
    hash = "sha256-z8d0m5b2O9McPEK1xHG/dWgUBT6EfBDz6wA0F7xSPTA=";
  };
in
assert lib.assertMsg (
  schemaProvenance.revision == schemaStoreRevision
) "gha-lint SchemaStore revision does not match schema-provenance.json";
bun2nix.mkDerivation {
  inherit (manifest) version;
  packageJson = ./package.json;
  module = "src/main.ts";
  src = ./.;

  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ./bun.nix;
  };

  bunInstallFlags = [
    "--frozen-lockfile"
    "--linker=isolated"
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ "--backend=symlink" ];

  dontRunLifecycleScripts = true;
  doCheck = true;
  GHA_LINT_WORKFLOW_SCHEMA = workflowSchema;
  GHA_LINT_ACTION_SCHEMA = actionSchema;

  postPatch = ''
    substituteInPlace src/shellcheck.ts \
      --replace-fail '@shellcheck@' '${lib.getExe shellcheck}'
  '';

  preBuild = ''
    bun run typecheck
  '';

  postInstall = ''
    "$out/bin/gha-lint" --help >/dev/null
    test "$("$out/bin/gha-lint" --version)" = "${manifest.version}"
    "$out/bin/gha-lint" tests/fixtures/valid-workflow.yaml
    "$out/bin/gha-lint" tests/fixtures/valid-action/action.yml
    "$out/bin/gha-lint" tests/fixtures/parallel-workflow.yaml

    set +e
    "$out/bin/gha-lint" --format json tests/fixtures/invalid-workflow.yaml >/dev/null
    status=$?
    set -e
    test "$status" -eq 1

    install -Dm644 schema-provenance.json \
      "$out/share/gha-lint/schema-provenance.json"
    install -Dm644 ${schemaStoreLicense} \
      "$out/share/licenses/gha-lint/SchemaStore-LICENSE"

    while IFS= read -r -d $'\0' licensePath; do
      relative="''${licensePath#node_modules/}"
      relative="''${relative#.bun/}"
      packagePath="''${relative%/*}"
      licenseName="$(printf '%s' "$packagePath" | tr '/@' '__')-$(basename "$licensePath")"
      install -Dm644 "$licensePath" "$out/share/licenses/gha-lint/$licenseName"
    done < <(find node_modules -type f \( -iname 'license' -o -iname 'license.*' \) -print0)
  '';

  meta = {
    description = "GitHub Actions workflow and action metadata validator";
    homepage = "https://github.com/cons-tan-tan/dotfiles";
    license = [
      lib.licenses.cc0
      lib.licenses.asl20
      lib.licenses.mit
      lib.licenses.isc
    ];
    mainProgram = "gha-lint";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };

  passthru.testSchemas = {
    workflow = workflowSchema;
    action = actionSchema;
  };
}
