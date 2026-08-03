{ inputs, ... }:
let
  systems = import inputs.supported-systems;
in
{
  inherit systems;
  den.systems = systems;
}
