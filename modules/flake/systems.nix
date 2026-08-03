{ inputs, ... }:
let
  systems = import inputs.supported-systems;
in
{
  den.systems = systems;
}
