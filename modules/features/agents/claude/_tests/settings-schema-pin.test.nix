let
  validatorSource = ../_interface/settings-validator.nix;
  pin = {
    url = "https://example.invalid/schema.json";
    hash = "sha256-schema-marker";
  };
  mkValidator =
    args:
    import validatorSource (
      {
        pkgs.fetchurl = attrs: attrs;
        schemaPin = import ../_interface/settings-schema.nix;
      }
      // args
    );
in
{
  testSettingsSchemaPinPropagates = {
    expr = {
      injected = (mkValidator { schemaPin = pin; }).schema;
      default = (mkValidator { }).schema;
    };
    expected = {
      injected = pin;
      default = import ../_interface/settings-schema.nix;
    };
  };
}
