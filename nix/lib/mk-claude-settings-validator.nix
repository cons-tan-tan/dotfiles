{
  pkgs,
  schemaPin ? builtins.fromJSON (builtins.readFile ../pins/claude-code-settings-schema.json),
}:
let
  schema = pkgs.fetchurl {
    inherit (schemaPin) url hash;
  };
in
{
  inherit schema;

  validate =
    name: source:
    pkgs.runCommand name
      {
        nativeBuildInputs = [ pkgs.check-jsonschema ];
      }
      ''
        check-jsonschema --schemafile ${schema} ${source}
        cp ${source} $out
      '';
}
