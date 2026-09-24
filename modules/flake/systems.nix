{ inputs, ... }:
let
  systems = import inputs.supported-systems;
in
{
  inherit systems;
}
