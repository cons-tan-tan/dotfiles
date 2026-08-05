{ fetchurl, lib }:
let
  schemaProvenance = lib.importJSON ./schema-provenance.json;
  schemaStoreRevision = "60cfa479d5901714547053ecee643a0a4c3a76fe";
  schemaStoreRaw = "https://raw.githubusercontent.com/SchemaStore/schemastore/${schemaStoreRevision}";
in
assert lib.assertMsg (
  schemaProvenance.revision == schemaStoreRevision
) "gha-lint SchemaStore revision does not match schema-provenance.json";
{
  schemas = {
    workflow = fetchurl {
      name = "github-workflow.json";
      url = "${schemaStoreRaw}/src/schemas/json/github-workflow.json";
      hash = "sha256-epUv23wbEwcy5AzOqdubztkGwRmOl4NPikmuO0EfMWE=";
    };
    action = fetchurl {
      name = "github-action.json";
      url = "${schemaStoreRaw}/src/schemas/json/github-action.json";
      hash = "sha256-g7078MQSLOt2SSe8GJ2eN5STEwa1PN+JgW9vNHLK34g=";
    };
  };

  schemaStoreLicense = fetchurl {
    name = "SchemaStore-LICENSE";
    url = "${schemaStoreRaw}/LICENSE";
    hash = "sha256-z8d0m5b2O9McPEK1xHG/dWgUBT6EfBDz6wA0F7xSPTA=";
  };

  fixtures = {
    workflow = ./tests/fixtures/valid-workflow.yaml;
    actionDirectory = ./tests/fixtures/valid-action;
  };
}
